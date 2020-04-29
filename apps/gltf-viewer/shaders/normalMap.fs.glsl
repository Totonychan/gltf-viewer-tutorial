#version 330

in vec3 vViewSpacePosition;
in vec3 vViewSpaceNormal;
in vec2 vTexCoords;

uniform vec3 uLightDirection;
uniform vec3 uLightIntensity;

uniform vec4 uBaseColorFactor;
uniform float uMetallicFactor;
uniform float uRougnessFactor;
uniform float uNormalFactor;
uniform vec3 uEmissiveFactor;

uniform sampler2D uBaseColorTexture;
uniform sampler2D uEmissiveTexture;
uniform sampler2D uMetallicRoughnessTexture;
uniform sampler2D uNormalTexture;

out vec3 fColor;

// Constants
const float GAMMA = 2.2;
const float INV_GAMMA = 1. / GAMMA;
const float M_PI = 3.141592653589793;
const float M_1_PI = 1.0 / M_PI;

// We need some simple tone mapping functions
// Basic gamma = 2.2 implementation
// Stolen here: https://github.com/KhronosGroup/glTF-Sample-Viewer/blob/master/src/shaders/tonemapping.glsl

// linear to sRGB approximation
// see http://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
vec3 LINEARtoSRGB(vec3 color)
{
  return pow(color, vec3(INV_GAMMA));
}

// sRGB to linear approximation
// see http://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
vec4 SRGBtoLINEAR(vec4 srgbIn)
{
  return vec4(pow(srgbIn.xyz, vec3(GAMMA)), srgbIn.w);
}



mat3 cotangent_frame(vec3 N, vec3 p, vec2 uv)
{
    // get edge vectors of the pixel triangle
    vec3 dp1 = dFdx( p );
    vec3 dp2 = dFdy( p );
    vec2 duv1 = dFdx( uv );
    vec2 duv2 = dFdy( uv );

    // solve the linear system
    vec3 dp2perp = cross( dp2, N );
    vec3 dp1perp = cross( N, dp1 );
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    // construct a scale-invariant frame
    float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
    return mat3( T * invmax, B * invmax, N );
}

vec3 perturb_normal( vec3 N, vec3 V)
{
    vec3 map = texture(uNormalTexture, vTexCoords).rgb;
    map = map * 255./127. - 128./127.;
    mat3 TBN = cotangent_frame(N, -V, vTexCoords);
    return normalize(TBN * map);
}

void main()
{
  vec3 N = normalize(vViewSpaceNormal);
  vec3 L = uLightDirection;
  vec3 V = normalize(-vViewSpacePosition);
  vec3 H = normalize(L + V);

  vec4 emissiveFromTexture = SRGBtoLINEAR(texture(uEmissiveTexture, vTexCoords));
  vec3 emissive = vec3(uEmissiveFactor * emissiveFromTexture.rgb);

  // NormalMap
  vec3 PN = perturb_normal( N, V);

    vec4 baseColorFromTexture = SRGBtoLINEAR(texture(uBaseColorTexture, vTexCoords));
    vec4 metallicRougnessFromTexture = texture(uMetallicRoughnessTexture, vTexCoords);
    vec4 baseColor = uBaseColorFactor * baseColorFromTexture;
    vec3 metallic = vec3(uMetallicFactor * metallicRougnessFromTexture.b);
    float roughness = uRougnessFactor * metallicRougnessFromTexture.g;

    vec3 dielectricSpecular = vec3(0.04);
    vec3 black = vec3(0.);

    vec3 c_diff = mix(baseColor.rgb * (1 - dielectricSpecular.r), black, metallic);
    vec3 F_0 = mix(vec3(dielectricSpecular) ,baseColor.rgb, metallic);
    float alpha = roughness * roughness;

    float VdotH = clamp(dot(V, H), 0, 1);
    float baseShlickFactor = 1 - VdotH;
    float shlickFactor = baseShlickFactor * baseShlickFactor; // power 2
    shlickFactor *= shlickFactor; // power 4
    shlickFactor *= baseShlickFactor; // power 5
    vec3 F = F_0 + (vec3(1) - F_0) * shlickFactor;

    float sqrAlpha = alpha * alpha;

    float NdotL = clamp(dot(PN, L), 0, 1);
    float NdotV = clamp(dot(PN, V), 0, 1);
    float visDenominator = NdotL * sqrt(NdotV * NdotV * (1 - sqrAlpha) + sqrAlpha) +
      NdotV * sqrt(NdotL * NdotL * (1 - sqrAlpha) + sqrAlpha);
    float Vis = visDenominator > 0. ? 0.5 / visDenominator : 0.0;

    float NdotH = clamp(dot(PN, H), 0, 1);
    float baseDenomD = (NdotH * NdotH * (sqrAlpha - 1) + 1);
    float D = M_1_PI * sqrAlpha / (baseDenomD * baseDenomD);

    vec3 f_specular = F * Vis * D;
    vec3 diffuse = c_diff * M_1_PI;
    vec3 f_diffuse = (1 - F) * diffuse;



    fColor = LINEARtoSRGB((f_diffuse + f_specular) * uLightIntensity * NdotL + emissive);
}
