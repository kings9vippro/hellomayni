#include "TouchCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <unordered_map>
#include <limits>
namespace {
constexpr size_t Capacity=8192;
struct Stroke {
 double last=-1, fx=0,fy=0,lx=0,ly=0,mx=0,my=0,xx=0,yy=0,xy=0;
 uint64_t n=0;
 void push(double x,double y) {
  if(!n){fx=x;fy=y;}
  lx=x-fx;ly=y-fy;++n;
  const double dx=lx-mx,dy=ly-my;
  mx+=dx/double(n);my+=dy/double(n);
  xx+=dx*(lx-mx);yy+=dy*(ly-my);xy+=dx*(ly-my);
 }
 double orthogonal() const {
  const double len=std::hypot(lx,ly);
  if(n<3||len<20)return -1;
  const double a=-ly/len,b=lx/len,mean=a*mx+b*my;
  return std::max(0.0,a*a*xx+2*a*b*xy+b*b*yy+double(n)*mean*mean);
 }
};
struct Core {
 TCStats s{};std::unordered_map<int64_t,Stroke> active;
 std::array<double,Capacity> gaps{},scratch{};
 size_t cursor=0, used=0;
 double delivery=0,square=0;uint64_t deviations=0,revision=0,snapshotRevision=std::numeric_limits<uint64_t>::max();
 double hz=0,p95=0;
 Core(){active.reserve(10);}
 void addGap(double v){gaps[cursor]=v;cursor=(cursor+1)%Capacity;used=std::min(used+1,Capacity);++revision;}
};
}
void* tc_create(){return new Core;}
void tc_destroy(void* p){delete static_cast<Core*>(p);}
void tc_reset(void* p){auto& c=*static_cast<Core*>(p);c.s={};c.active.clear();c.cursor=c.used=0;c.delivery=c.square=0;c.deviations=0;c.hz=c.p95=0;++c.revision;c.snapshotRevision=std::numeric_limits<uint64_t>::max();}
void tc_begin(void* p,int64_t id){auto& c=*static_cast<Core*>(p);c.active.try_emplace(id);c.s.peak_fingers=std::max(c.s.peak_fingers,static_cast<int32_t>(c.active.size()));}
void tc_sample(void* p,int64_t id,double t,double x,double y,double now){
 auto& c=*static_cast<Core*>(p);auto it=c.active.find(id);
 if(it==c.active.end()||!std::isfinite(t)||!std::isfinite(x)||!std::isfinite(y))return;
 auto& a=it->second;if(t<=a.last)return;
 if(a.last>=0){double gap=(t-a.last)*1000;if(gap>0&&gap<=1000){c.addGap(gap);++c.s.intervals;}}
 a.last=t;++c.s.samples;double lag=(now-t)*1000;
 if(std::isfinite(lag)&&lag>=0&&lag<=1000){c.delivery+=lag;++c.s.latency_count;}
 a.push(x,y);
}
void tc_end(void* p,int64_t id,int32_t cancelled){
 auto& c=*static_cast<Core*>(p);auto it=c.active.find(id);if(it==c.active.end())return;
 if(cancelled)++c.s.cancelled;
 else {double square=it->second.orthogonal();if(square>=0){++c.s.strokes;c.square+=square;c.deviations+=it->second.n;}}
 c.active.erase(it);
}
TCStats tc_stats(void* p){
 auto& c=*static_cast<Core*>(p);auto s=c.s;
 if(c.snapshotRevision!=c.revision){
  c.snapshotRevision=c.revision;
  if(c.used){auto a=c.scratch.begin(),z=a+c.used;std::copy_n(c.gaps.begin(),c.used,a);
   size_t mid=c.used/2;std::nth_element(a,a+mid,z);double m=a[mid];if(c.used%2==0)m=(m+*std::max_element(a,a+mid))/2;
   size_t k=static_cast<size_t>(std::ceil(c.used*.95))-1;std::nth_element(a,a+k,z);c.hz=1000/m;c.p95=a[k];
  }
 }
 s.median_hz=c.hz;s.p95_gap_ms=c.p95;
 if(s.latency_count)s.mean_delivery_ms=c.delivery/s.latency_count;
 if(c.deviations)s.straight_rms_pt=std::sqrt(c.square/c.deviations);
 return s;
}
