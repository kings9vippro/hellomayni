#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position;
    float4 color;
};

struct RasterVertex {
    float4 position [[position]];
    float4 color;
};

vertex RasterVertex touch_vertex(const device Vertex* vertices [[buffer(0)]],
                                uint index [[vertex_id]]) {
    return {float4(vertices[index].position, 0, 1), vertices[index].color};
}

fragment float4 touch_fragment(RasterVertex input [[stage_in]]) {
    return input.color;
}
