// Notchly temps v2: полная карта сенсоров M2 + мониторинг (cpu/память/swap/load/uptime).
// Раскладка ядер проверена нагрузочным тестом 17.10.2026 (8x yes):
//   пары ключей (Tp01,Tp02),(Tp05,Tp06),(Tp09,Tp0A),(Tp0D,Tp0E):
//   второй в паре горячее и при простое, и под нагрузкой -> performance,
//   первый -> efficiency. Прочее сверено со скриншотом Temperatures.
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <unistd.h>
#include <ctime>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>
#include <libproc.h>
#include "smctemp.h"

static double clampV(double v) { return (v > 5.0 && v < 140.0) ? v : 0.0; }

static void printArray(smctemp::SmcAccessor& acc, const std::vector<std::string>& keys, bool last) {
  printf("[");
  for (size_t i = 0; i < keys.size(); i++) {
    printf("%.1f%s", clampV(acc.ReadValue(keys[i].c_str())), i + 1 < keys.size() ? "," : "");
  }
  printf("]%s", last ? "" : ",");
}

static void printScalar(smctemp::SmcAccessor& acc, const char* key, bool last) {
  printf("%.1f%s", clampV(acc.ReadValue(key)), last ? "" : ",");
}

static void cpuPercents(std::vector<double>& out) {
  out.clear();
  natural_t nCpu = 0;
  processor_info_array_t i1 = nullptr, i2 = nullptr;
  mach_msg_type_number_t c1 = 0, c2 = 0;
  kern_return_t k1 = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &nCpu, &i1, &c1);
  if (k1 != KERN_SUCCESS || nCpu == 0 || nCpu > 64) return;
  usleep(350000);
  kern_return_t k2 = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &nCpu, &i2, &c2);
  if (k2 != KERN_SUCCESS) {
    vm_deallocate(mach_task_self(), (vm_address_t)i1, c1 * sizeof(integer_t));
    return;
  }
  for (natural_t i = 0; i < nCpu; i++) {
    processor_cpu_load_info_t r1 = (processor_cpu_load_info_t)&i1[i * PROCESSOR_CPU_LOAD_INFO_COUNT];
    processor_cpu_load_info_t r2 = (processor_cpu_load_info_t)&i2[i * PROCESSOR_CPU_LOAD_INFO_COUNT];
    long t1 = 0, t2 = 0;
    for (int s = 0; s < CPU_STATE_MAX; s++) { t1 += r1->cpu_ticks[s]; t2 += r2->cpu_ticks[s]; }
    long di = (long)r2->cpu_ticks[CPU_STATE_IDLE] - (long)r1->cpu_ticks[CPU_STATE_IDLE];
    long dt = t2 - t1;
    out.push_back(dt > 0 ? (double)(dt - di) * 100.0 / (double)dt : 0.0);
    if (out.back() < 0) out.back() = 0;
    if (out.back() > 100) out.back() = 100;
  }
  vm_deallocate(mach_task_self(), (vm_address_t)i1, c1 * sizeof(integer_t));
  vm_deallocate(mach_task_self(), (vm_address_t)i2, c2 * sizeof(integer_t));
}

int main() {
  smctemp::SmcAccessor acc;
  printf("{\"ecore\":"); printArray(acc, {"Tp01","Tp05","Tp09","Tp0D"}, false);
  printf("\"pcore\":");   printArray(acc, {"Tp02","Tp06","Tp0A","Tp0E"}, false);
  printf("\"pkg\":");     printScalar(acc, "TPMP", false);
  printf("\"gpu\":");     printArray(acc, {"Tg0f","Tg0n"}, false);
  printf("\"batt\":");    printArray(acc, {"TB0T","TAOL","TB1T","TB2T"}, false);
  printf("\"trackpad\":");printArray(acc, {"TDBP","TDeL"}, false);
  printf("\"charger\":"); printScalar(acc, "TCHP", false);
  printf("\"psu\":");     printScalar(acc, "TPSP", false);
  printf("\"tb\":");      printScalar(acc, "TIOP", false);
  printf("\"wifi\":");    printScalar(acc, "TW0P", false);
  printf("\"ssd\":");     printScalar(acc, "TH0x", false);

  // Ядра CPU, %
  std::vector<double> cpus;
  cpuPercents(cpus);
  printf("\"cores\":[");
  for (size_t i = 0; i < cpus.size(); i++) printf("%.0f%s", cpus[i], i + 1 < cpus.size() ? "," : "");
  printf("],");

  // Память, МБ
  vm_size_t pageSize = 4096;
  host_page_size(mach_host_self(), &pageSize);
  vm_statistics64_data_t vs; mach_msg_type_number_t vc = HOST_VM_INFO64_COUNT;
  uint64_t memTotal = 0, memUsed = 0;
  size_t sz = sizeof(memTotal);
  if (sysctlbyname("hw.memsize", &memTotal, &sz, nullptr, 0) == 0 &&
      host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vs, &vc) == KERN_SUCCESS) {
    uint64_t freeish = (uint64_t)(vs.free_count + vs.inactive_count + vs.speculative_count) * pageSize;
    memUsed = memTotal > freeish ? memTotal - freeish : 0;
  }
  printf("\"mem\":{\"used\":%llu,\"total\":%llu},", (unsigned long long)(memUsed >> 20), (unsigned long long)(memTotal >> 20));

  // Swap, МБ
  double swT = 0, swU = 0;
  if (FILE* pf = popen("/usr/sbin/sysctl -n vm.swapusage 2>/dev/null", "r")) {
    char sw[256] = {0};
    size_t n = fread(sw, 1, sizeof(sw) - 1, pf);
    pclose(pf); (void)n;
    char* t = strstr(sw, "total ="); char* u = strstr(sw, "used =");
    if (t) swT = atof(t + 7); if (u) swU = atof(u + 6);
  }
  printf("\"swap\":{\"used\":%.0f,\"total\":%.0f},", swU, swT);

  // Load average
  double la[3] = {0, 0, 0};
  getloadavg(la, 3);
  printf("\"load\":[%.2f,%.2f,%.2f],", la[0], la[1], la[2]);

  // Задачи и потоки
  int tasks = proc_listallpids(nullptr, 0);
  int threads = 0;
  int nTask = 0, nThr = 0; sz = sizeof(int);
  if (sysctlbyname("kern.num_taskthreads", &nThr, &sz, nullptr, 0) == 0 && nThr > 0) threads = nThr;
  if (tasks <= 0 && sysctlbyname("kern.num_tasks", &nTask, &sz, nullptr, 0) == 0) tasks = nTask;
  printf("\"tasks\":%d,\"threads\":%d,", tasks, threads);

  // Аптайм
  struct timeval bt; memset(&bt, 0, sizeof(bt)); sz = sizeof(bt);
  long up = 0;
  if (sysctlbyname("kern.boottime", &bt, &sz, nullptr, 0) == 0) up = (long)(time(nullptr) - bt.tv_sec);
  printf("\"uptime\":%ld}\n", up);
  return 0;
}
