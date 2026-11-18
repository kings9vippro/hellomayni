#include "TouchCore.h"
#include <algorithm>
#include <cmath>
#include <deque>
#include <unordered_map>
#include <vector>
struct Point {double x,y;};
struct Stroke {double last=-1; std::vector<Point> points;};
struct Core {TCStats s{}; std::unordered_map<int64_t,Stroke> active; std::deque<double> gaps; double delivery=0, square=0; uint64_t deviations=0;};
void* tc_create(){return new Core;}
void tc_destroy(void* p){delete static_cast<Core*>(p);}
void tc_reset(void* p){*static_cast<Core*>(p)=Core{};}
void tc_begin(void* p,int64_t id){auto& c=*static_cast<Core*>(p); c.active.try_emplace(id);c.s.peak_fingers=std::max(c.s.peak_fingers,static_cast<int32_t>(c.active.size()));}
void tc_sample(void* p,int64_t id,double t,double x,double y,double now){
 auto& c=*static_cast<Core*>(p);auto it=c.active.find(id);if(it==c.active.end()||!std::isfinite(t)||!std::isfinite(x)||!std::isfinite(y))return;auto& a=it->second;
 if(t<=a.last)return;
 if(a.last>=0){double gap=(t-a.last)*1000;if(gap>0&&gap<=1000){c.gaps.push_back(gap);if(c.gaps.size()>8192)c.gaps.pop_front();++c.s.intervals;}}
 a.last=t;++c.s.samples;double lag=(now-t)*1000;if(std::isfinite(lag)&&lag>=0&&lag<=1000){c.delivery+=lag;++c.s.latency_count;}
 if(a.points.size()<8192)a.points.push_back({x,y});
}
void tc_end(void* p,int64_t id,int32_t cancelled){
 auto& c=*static_cast<Core*>(p);auto it=c.active.find(id);if(it==c.active.end())return;auto& a=it->second.points;
 if(cancelled)++c.s.cancelled;
 else if(a.size()>=3){auto f=a.front(), l=a.back();double dx=l.x-f.x,dy=l.y-f.y,d=std::hypot(dx,dy);if(d>=20){++c.s.strokes;for(auto q:a){double v=((q.x-f.x)*dy-(q.y-f.y)*dx)/d;c.square+=v*v;++c.deviations;}}}
 c.active.erase(it);
}
TCStats tc_stats(void* p){auto& c=*static_cast<Core*>(p);auto s=c.s;std::vector<double> v(c.gaps.begin(),c.gaps.end());if(!v.empty()){size_t n=v.size(), mid=n/2;std::nth_element(v.begin(),v.begin()+mid,v.end());double m=v[mid];if(n%2==0)m=(m+*std::max_element(v.begin(),v.begin()+mid))/2;size_t k=static_cast<size_t>(std::ceil(n*.95))-1;std::nth_element(v.begin(),v.begin()+k,v.end());s.median_hz=1000/m;s.p95_gap_ms=v[k];}if(s.latency_count)s.mean_delivery_ms=c.delivery/s.latency_count;if(c.deviations)s.straight_rms_pt=std::sqrt(c.square/c.deviations);return s;}
