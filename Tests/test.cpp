#include "TouchCore.h"
#include <cassert>
#include <cmath>
int main(){auto p=tc_create();tc_begin(p,1);tc_begin(p,2);for(int i=0;i<100;++i){double t=1+i/120.;tc_sample(p,1,t,i,0,t+.004);tc_sample(p,1,t,i,0,t+.004);}tc_end(p,1,0);tc_end(p,2,1);auto s=tc_stats(p);assert(s.samples==100&&s.intervals==99&&s.peak_fingers==2&&s.cancelled==1&&s.strokes==1);assert(std::abs(s.median_hz-120)<.001&&std::abs(s.mean_delivery_ms-4)<.001&&s.straight_rms_pt==0);tc_reset(p);assert(tc_stats(p).samples==0);tc_begin(p,1);
for(int i=0;i<50000;++i){double t=1+i/120.;tc_sample(p,1,t,i,0,t+.004);}
tc_end(p,1,0);s=tc_stats(p);assert(s.samples==50000&&s.strokes==1&&s.straight_rms_pt<1e-8&&std::abs(s.median_hz-120)<.001);
tc_reset(p);tc_begin(p,2);tc_sample(p,2,1,0,0,1);tc_sample(p,2,2,10,3,2);tc_sample(p,2,3,20,0,3);tc_end(p,2,0);s=tc_stats(p);assert(std::abs(s.straight_rms_pt-std::sqrt(3.))<.00001);tc_destroy(p);}
