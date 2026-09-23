// Données M1 synthétiques : marche aléatoire à volatilité variable, phases de tendance,
// trous de données et week-ends. Prix quantifiés au tick de 0.25 (type NQ).
#pragma once
#include <algorithm>
#include <cmath>
#include <random>
#include <vector>

#include "mql5_core.h"

struct Bar {
  datetime t;
  double o, h, l, c;
};

inline std::vector<Bar> synth(int n, unsigned seed, datetime t0) {
  std::mt19937_64 rng(seed);
  std::normal_distribution<double> N(0.0, 1.0);
  std::uniform_real_distribution<double> U(0.0, 1.0);
  std::vector<Bar> v;
  v.reserve(n);
  double px = 18000.0, vol = 4.0, drift = 0.0;
  datetime t = t0;
  for (int i = 0; i < n; i++) {
    if (U(rng) < 0.01) drift = N(rng) * 1.5;
    vol = std::max(1.0, std::min(20.0, vol * std::exp(0.05 * N(rng))));
    double o = px;
    double c = o + drift + vol * N(rng);
    double h = std::max(o, c) + std::fabs(N(rng)) * vol * 0.6;
    double l = std::min(o, c) - std::fabs(N(rng)) * vol * 0.6;
    auto q = [](double x) { return std::round(x * 4.0) / 4.0; };
    Bar b = {t, q(o), q(h), q(l), q(c)};
    b.h = std::max(b.h, std::max(b.o, b.c));
    b.l = std::min(b.l, std::min(b.o, b.c));
    v.push_back(b);
    px = b.c;
    t += 60;
    if (U(rng) < 0.002) t += 60 * (1 + (int)(U(rng) * 30));  // trous de données
    MqlDateTime s;
    TimeToStruct(t, s);
    if (s.day_of_week == 6) t += 2 * 86400;  // saute le week-end
  }
  return v;
}
