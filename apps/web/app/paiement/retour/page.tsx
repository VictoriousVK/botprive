import type { Metadata } from "next";
import { getPaymentForMember } from "@vk/core";
import { PaymentStatus } from "@/components/PaymentStatus";
import { getCurrentMember, getDeps } from "@/lib/server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Paiement", robots: { index: false } };

/**
 * Page de retour après paiement. Elle AFFICHE le statut mais n'accorde jamais l'accès :
 * seul le webhook signé + la vérification serveur à serveur le font.
 */
export default async function RetourPage({ searchParams }: { searchParams: Promise<{ ref?: string; annule?: string }> }) {
  const sp = await searchParams;
  const deps = getDeps();
  const member = await getCurrentMember();
  const payment = member && sp.ref ? await getPaymentForMember(deps, member.id, sp.ref) : null;

  return (
    <div className="container page page-narrow">
      <p className="label">Paiement</p>
      <h1 className="display" style={{ fontSize: "clamp(2.6rem, 11vw, 4.6rem)" }}>
        {sp.annule ? "Paiement interrompu" : "Merci !"}
      </h1>
      {payment ? (
        <PaymentStatus reference={payment.reference} initial={sp.annule && payment.status === "pending" ? "failed" : payment.status} inviteUrl={deps.env.DISCORD_INVITE_URL} />
      ) : (
        <div className="alert" role="status">
          Si ton paiement est validé, ton accès est activé automatiquement dans quelques instants : tu recevras un message Discord et un
          email. Tu peux suivre ton abonnement dans ton <a href="/espace">espace membre</a>.
        </div>
      )}
    </div>
  );
}
