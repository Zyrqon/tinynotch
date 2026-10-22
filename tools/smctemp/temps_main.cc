// Notchly temps: читает сенсоры Apple Silicon (M2) и печатает JSON.
// Сопоставление ключей проверено нагрузочным тестом 17.10.2026:
//   Ключи CPU/GPU - официальная раскладка M2 из Stats (exelban),
//   проверена нагрузочным тестом 17.10 (Tp0A до 104C при 8x yes, как в Temperatures).
//   TPD0..7 - только датчики домена питания, для ядер НЕ годятся.
//   SoC: TCMb/TCMz, skin: TCHP/TH0T/TMVR, batt: TB0T/TB1T.
#include <cstdio>
#include <string>
#include <vector>
#include "smctemp.h"

int main() {
  smctemp::SmcAccessor acc;
  struct G { const char* name; std::vector<std::string> keys; };
  std::vector<G> groups = {
    {"cpu",  {"Tp0A","Tp0D","Tp0E","Tp01","Tp02","Tp05","Tp06","Tp09"}},
    {"gpu",  {"Tg0f","Tg0j"}},
    {"soc",  {"TCMb","TCMz"}},
    {"skin", {"TCHP","TH0T","TMVR"}},
    {"batt", {"TB0T","TB1T"}},
  };
  printf("{");
  bool firstG = true;
  for (auto& g : groups) {
    double best = 0.0; bool got = false;
    for (auto& k : g.keys) {
      double v = acc.ReadValue(k.c_str());
      if (v > 5.0 && v < 140.0) { if (!got || v > best) { best = v; got = true; } }
    }
    printf("%s\"%s\":%.1f", firstG ? "" : ",", g.name, got ? best : 0.0);
    firstG = false;
  }
  printf("}\n");
  return 0;
}
