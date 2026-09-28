# ICT NAS Institutional — correctifs v2.20 → v2.21

Pourquoi l'EA ne prenait aucune position, et les blocs à remplacer dans `ICT_NAS_Institutional.mq5`.
Tous les blocs se collent dans MetaEditor ; rien d'autre ne change.

## Causes du « zéro trade »

1. **Cible trop proche → `REJECTED_RISK (RR < min)`** (cause n°1).
   Silver Bullet, Killzone et SB Momentum visaient le pool de liquidité **le plus proche**.
   Avec un RR minimum de 3, ce pool est presque toujours à moins de 3R → rejet.
   La cible de secours à 3R ne servait que s'il n'y avait **aucune** liquidité.
   En ICT, la liquidité dans le sens du trade est un aimant, pas un obstacle :
   la DOL devient désormais le **premier pool intact situé à au moins RR min** (ensuite plafonné à MaxRR).
2. **Égalité en virgule flottante.** La cible de secours vaut `entrée + 3R`, puis on recalcule
   `RR = |cible - entrée| / R` : on obtient souvent 2.9999999 < 3.0 → rejet `RR 3.00 < 3.0`.
   Même problème pour le score (25 contre 25 quand des poids JSON sont chargés).
3. **SL ramené à l'intérieur du sweep.** Le plafond de 2.5 ATR M5 tirait le SL **sous** l'extrême
   du sweep, ce qui n'est pas ICT et donne des stops pris par la mèche. Désormais :
   SL toujours au-delà du sweep ; s'il est trop large, on prend le SL ICT alternatif au-delà de la
   **bougie 1 du FVG** ; si ce SL est encore trop large, le setup est rejeté et la raison est enregistrée.
4. **Ordres limites refusés par le broker.** `SetTypeFillingBySymbol` impose FOK/IOC, que beaucoup de
   brokers CFD refusent sur un ordre en attente (retcode 10030), et certains refusent aussi `GTC`.
   Maintenant : nouvel essai avec les autres modes de remplissage, et type d'expiration choisi selon le symbole.
5. **Position au marché perdue.** Si la position n'apparaissait pas encore au tick suivant, le contexte
   était supprimé (plus de TP1 partiel, plus de BE). Un délai de grâce de 60 s est ajouté.

## Avant de tester

- Testeur : **« Every tick based on real ticks »** et symbole NAS100/US100 avec un historique M1 complet.
- Lire le bloc `===== DIAGNOSTIC =====` dans le journal : il montre à quelle étape les setups meurent
  (sweeps → MSS/CISD → displacement → FVG → modèle → décision).
- Au premier lancement en live, vérifier la ligne `Fuseau serveur verifie`. Si elle affiche
  `ATTENTION fuseau`, toutes les fenêtres (killzones, SB, OPR) sont décalées : corriger `InpServerTZ`.

---

## Bloc 1 — version (en-tête et Defines)

```mql5
#property version   "2.21"
```
```mql5
#define ICTNAS_VERSION  "2.21"
```

## Bloc 2 — `struct SSetup` (SetupEngine) : ajouter un champ

Après la ligne `datetime          fvgT1;`, ajouter :

```mql5
   double            fvgC1Ext;         // extrême de la bougie 1 du FVG côté SL (SL ICT alternatif)
```

## Bloc 3 — `CSetupEngine::Evaluate` : remplir ce champ

Après la ligne `s.fvgT1=r[i1].time;`, ajouter :

```mql5
      s.fvgC1Ext=Unmirror(r[i1].high,h.dir==1?1:-1);
```

## Bloc 4 — `ScanMomentum` : initialiser le champ

Remplacer :
```mql5
   c.fvgTop=top; c.fvgBottom=bot; c.fvgT1=t1;
```
par :
```mql5
   c.fvgTop=top; c.fvgBottom=bot; c.fvgT1=t1; c.fvgC1Ext=0;
```

## Bloc 5 — ModelRouter : tolérance RR, sélection de la DOL

### 5a. Juste après la fonction `STDVTarget(...)`, ajouter :

```mql5
#define RR_EPS 0.01                 // tolérance sur les comparaisons de RR (virgule flottante)
int g_liqTargetW=0;                 // >0 : la DOL est choisie dans la carte de liquidité (poids min)

//--- DOL ICT : premier pool de liquidité intact (poids >= minW) situé à au moins g_pMinRR x R.
//--- Les pools plus proches sont des aimants sur le chemin, pas des obstacles. 0 = aucun.
double PickLiquidityDOL(int dir,double entry,double r,int minW)
  {
   if(r<=0) return(0);
   for(int skip=0;skip<10;skip++)
     {
      int k=g_liq.NextIntact(dir==1,entry,minW,skip);
      if(k<0) break;
      if(dir*(g_liq.lv[k].price-entry)>=(g_pMinRR-RR_EPS)*r) return(g_liq.lv[k].price);
     }
   return(0);
  }
```

### 5b. Dans `CRTTarget`, remplacer :
```mql5
      if(r>0 && d>=g_pMinRR*r && d<dFar) { dFar=d; bestFar=cands[i]; }
```
par :
```mql5
      if(r>0 && d>=(g_pMinRR-RR_EPS)*r && d<dFar) { dFar=d; bestFar=cands[i]; }
```

### 5c. Dans `ChooseModel` :

Remplacer :
```mql5
   dol=0; runner=0; hasRef=false;
```
par :
```mql5
   dol=0; runner=0; hasRef=false; g_liqTargetW=0;
```

Dans le bloc Momentum, remplacer :
```mql5
      model="SB_MOMENTUM";
```
par :
```mql5
      model="SB_MOMENTUM";
      g_liqTargetW=4;
```

Dans le bloc Silver Bullet, juste **après** la fin du bloc TGIF (juste avant
`int k=g_liq.NextIntact(c.dir==1,c.CE(),InpSBMinTargetWeight);`), ajouter :
```mql5
      g_liqTargetW=InpSBMinTargetWeight;
```

Dans le bloc Killzone, remplacer :
```mql5
      model="KILLZONE";
```
par :
```mql5
      model="KILLZONE";
      g_liqTargetW=4;
```

## Bloc 6 — `BuildSignal` : SL ICT et cible

Remplacer tout le passage qui va de
```mql5
   s.sl=c.extreme-c.dir*InpSLBufferPts;
```
jusqu'à (inclus)
```mql5
   if(crt) dol=CRTTarget(c.dir,s.entry,r,g_crtExtra);
```
par :

```mql5
   //--- SL ICT : TOUJOURS au-delà de l'extrême du sweep (+ buffer)
   string preReject="";
   s.sl=c.extreme-c.dir*InpSLBufferPts;
   double atr5=g_atr.Get(PERIOD_M5);
   if(atr5>0 && c.dir*(s.entry-s.sl)>0)
     {
      double dist=c.dir*(s.entry-s.sl);
      double lo=g_pSLFloorATR*atr5,hi=g_pSLCapATR*atr5;
      //--- plancher : jamais plus serré que x ATR M5 (on élargit, on ne rentre jamais dans le sweep)
      if(g_pSLFloorATR>0 && dist<lo) dist=lo;
      //--- plafond : sweep trop loin -> SL au-delà de la bougie 1 du FVG ; sinon setup rejeté
      if(g_pSLCapATR>0 && dist>hi)
        {
         double alt=(c.fvgC1Ext!=0)?c.fvgC1Ext-c.dir*InpSLBufferPts:0;
         double altDist=(alt!=0)?c.dir*(s.entry-alt):0;
         if(altDist>0 && altDist<=hi) dist=MathMax(altDist,(g_pSLFloorATR>0)?lo:0.0);
         else preReject="SL trop large ("+DoubleToString(dist,1)+" > "+DoubleToString(hi,1)+" pts)";
        }
      s.sl=s.entry-c.dir*dist;
     }
   if(c.dir*(s.entry-s.sl)<=0) return(false);            // entrée déjà au-delà du SL
   s.riskPts=MathAbs(s.entry-s.sl);
   double r=s.riskPts;
   if(crt) dol=CRTTarget(c.dir,s.entry,r,g_crtExtra);
   //--- modèles "liquidité" (SB, Killzone, Momentum) : DOL = 1er pool intact à >= RR min
   if(g_liqTargetW>0)
     {
      double d2=PickLiquidityDOL(c.dir,s.entry,r,g_liqTargetW);
      if(d2>0) dol=d2;
      else if(g_pFallbackRR>0) dol=0;                     // aucun pool assez loin -> cible de secours
     }
```

Toujours dans `BuildSignal`, remplacer la dernière ligne avant `return(true);` :
```mql5
   s.mlProb=-1; s.mlModel=""; s.score=0; s.decision=""; s.reason=""; s.taken=false;
```
par :
```mql5
   s.mlProb=-1; s.mlModel=""; s.score=0; s.taken=false;
   s.decision=(preReject!="")?"REJECTED_RISK":"";
   s.reason=preReject;
```

## Bloc 7 — `Decide` : pré-rejet et tolérances

Après le bloc ML :
```mql5
   if(InpMLMode!=ML_OFF && g_ml.Ready())
     {
      s.mlProb=g_ml.Predict(s,f);
      s.mlModel=g_ml.ModelId();
     }
```
ajouter :
```mql5
   if(s.decision!="") return;                              // rejeté dès la construction (SL trop large)
```

Remplacer :
```mql5
   if(s.planRR<g_pMinRR)
```
par :
```mql5
   if(s.planRR<g_pMinRR-RR_EPS)
```

Remplacer :
```mql5
   if(s.score<g_pScoreMin) { s.decision="REJECTED_SCORE"; s.reason="score "+DoubleToString(s.score,0); return; }
```
par :
```mql5
   if(s.score<g_pScoreMin-1e-6) { s.decision="REJECTED_SCORE"; s.reason="score "+DoubleToString(s.score,0); return; }
```

## Bloc 8 — `CTradeManager` : exécution robuste

### 8a. Dans la section `private:` de `CTradeManager` (par exemple juste après `VMin`), ajouter :

```mql5
   //--- Type d'expiration accepté par le symbole (certains brokers refusent GTC)
   ENUM_ORDER_TYPE_TIME PendingTimeType(void)
     {
      int m=(int)SymbolInfoInteger(m_sym,SYMBOL_EXPIRATION_MODE);
      if((m&SYMBOL_EXPIRATION_GTC)!=0) return(ORDER_TIME_GTC);
      if((m&SYMBOL_EXPIRATION_SPECIFIED)!=0) return(ORDER_TIME_SPECIFIED);
      return(ORDER_TIME_DAY);
     }
```

### 8b. Dans `Place(...)`, remplacer le passage qui va de
```mql5
      bool ok=false;
      bool market=false;
```
jusqu'à (inclus)
```mql5
      uint rc=m_trade.ResultRetcode();
```
par :

```mql5
      double pxNow=(s.dir==1)?ask:bid;
      if(s.inval>0 && s.dir*(pxNow-s.inval)<0) { err="FVG deja pris a plus de 50 %"; return(false); }
      //--- 0 = marché, 1 = limite au CE / bord du FVG
      int kind=-1;
      if(s.market) kind=0;
      else if(s.dir==1)
        {
         if(ask>entry+stops) kind=1;
         else if(ask>sl && ask<=s.fvgTop) kind=0;
        }
      else
        {
         if(bid<entry-stops) kind=1;
         else if(bid<sl && bid>=s.fvgBot) kind=0;
        }
      if(kind<0) { err="prix hors zone d'entree"; return(false); }
      if(kind==0 && MathAbs(pxNow-sl)<=stops) { err="SL trop proche (stops level)"; return(false); }
      bool market=(kind==0);
      ENUM_ORDER_TYPE_TIME tt=PendingTimeType();
      datetime exp=0;
      if(tt==ORDER_TIME_SPECIFIED) exp=MathMax(s.expirySrv,TimeCurrent()+120);
      //--- nouvel essai avec un autre mode de remplissage si le broker refuse (retcode 10030)
      ENUM_ORDER_TYPE_FILLING fills[3]={ORDER_FILLING_RETURN,ORDER_FILLING_IOC,ORDER_FILLING_FOK};
      bool ok=false;
      uint rc=0;
      for(int a=0;a<4;a++)
        {
         if(a==0) m_trade.SetTypeFillingBySymbol(m_sym);
         else     m_trade.SetTypeFilling(fills[a-1]);
         if(market) ok=(s.dir==1)?m_trade.Buy(lots,m_sym,0,sl,tp,cmt):m_trade.Sell(lots,m_sym,0,sl,tp,cmt);
         else       ok=(s.dir==1)?m_trade.BuyLimit(lots,entry,m_sym,sl,tp,tt,exp,cmt)
                                 :m_trade.SellLimit(lots,entry,m_sym,sl,tp,tt,exp,cmt);
         rc=m_trade.ResultRetcode();
         if(rc!=TRADE_RETCODE_INVALID_FILL) break;
        }
      m_trade.SetTypeFillingBySymbol(m_sym);
```

Supprimez aussi, plus haut dans `Place`, les deux lignes d'origine désormais en double :
```mql5
      double pxNow=(s.dir==1)?ask:bid;
      if(s.inval>0 && s.dir*(pxNow-s.inval)<0) { err="FVG deja pris a plus de 50 %"; return(false); }
```
Elles se trouvent juste après `bool market=false;` dans la version d'origine. Si vous avez remplacé tout le
passage ci-dessus d'un seul bloc, elles ont déjà disparu : vérifiez simplement qu'il n'en reste qu'une copie.

### 8c. Dans `OnTick()` de `CTradeManager` (branche « ordre en attente »), remplacer :
```mql5
            else
               m_t[i].active=false;           // annulé / rejeté par le serveur
```
par :
```mql5
            else if(now-m_t[i].tPlaced>60)
               m_t[i].active=false;           // annulé / rejeté / expiré (délai de grâce : la position peut apparaître en retard)
```

---

## Ce qui ne change pas (volontairement)

- La séquence ICT reste obligatoire : Sweep → MSS/CISD → Displacement → FVG → entrée au CE.
- RR minimum 3, TP1 50 % à 2R, BE à 1R, DOL plafonnée à 5R (profil Standard).
- Le ML reste en observation et ne crée ni ne modifie aucun signal.

## Si l'EA ne trade toujours pas, lire le diagnostic

| Étape bloquée dans le DIAGNOSTIC | Réglage à essayer |
|---|---|
| `1. Liquidites prises : 0` | mode de ticks du testeur, historique M1, `InpServerTZ` |
| Beaucoup de `cassure sans displacement` | `InpProfile=Personnalise` et `InpDispATRMult` à 1.0-1.2 |
| Beaucoup de `pas de FVG valide` | `InpMinFVGPts` à 2-3 (M1) ou `InpExecTF=M3` |
| `4. hors fenetre` élevé | normal hors killzones ; vérifier le fuseau |
| `REJECTED_RISK (RR < min)` | `InpMinRR` à 2 (profil Personnalisé) |
| `REJECTED_RISK (SL trop large ...)` | `InpSLCapATR` à 3-3.5 |
| `REJECTED_RISK (ordre refuse (...))` | lire le retcode : lot, stops level, marché fermé |
| `REJECTED_RISK (lot < lot minimum)` | le risque de 3 % ne couvre pas le lot minimum sur ce SL : compte trop petit |
