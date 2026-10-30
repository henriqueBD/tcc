shader_type canvas_item;
render_mode unshaded;

// Used for tile terrain that does not have sprites
// Also can be used for large objets like houses 

// Same value as TimeManager.sun_direction: the ground direction shadows fall.
global uniform vec2 sun_direction;
global uniform float sun_strength;

uniform vec4 color : source_color;
uniform float max_dist : hint_range(0.0, 1000.0) = 100.0;
// Must match SkewShadowSprite.perspective_squash.
uniform float perspective_squash : hint_range(0.0, 1.0) = 0.64;
uniform sampler2D gradientTexture;

const int MAX_STEPS = 64;

vec4 get_gradient_color(float position) {
    return texture(gradientTexture, vec2(position, 0.5));
}

void fragment() {
    // On screen, sprite shadows point along the squashed sun direction.
    vec2 shadow_dir = vec2(sun_direction.x, sun_direction.y * perspective_squash);
    float len = length(shadow_dir);
    // March toward the light (opposite the shadow) looking for an occluder.
    vec2 march_dir = len > 0.0001 ? -shadow_dir / len : vec2(0.0);

    vec2 at = screen_uv_to_sdf(SCREEN_UV);
    float accum = 0.0;
    bool hit = false; // Tracks if we actually collided with an occluder

    for (int i = 0; i < MAX_STEPS; i++) {
        float d = texture_sdf(at);
        if (d < 0.01) {
            hit = true;
            break;
        }
        accum += d;
        if (accum >= max_dist) {
            break;
        }
        at += d * march_dir;
    }
    
    float alpha = 0.0; // Default to no shadow
    
    if (hit) {
        alpha = 1.0 - min(1.0, accum / max_dist);
        // The gradient controls the falloff of the shadow.
        alpha = get_gradient_color(alpha).r;
    }

    // Apply the global sun strength to the shadow intensity
    alpha *= sun_strength;

    COLOR = vec4(color.rgb, alpha * color.a);
}