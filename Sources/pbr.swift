import simd

func randomFloat() -> Float {
    return Float.random(in: 0..<1)
}

func reflect(_ incident: SIMD3<Float>, _ normal: SIMD3<Float>) -> SIMD3<Float> {
    return incident - 2 * dot(incident, normal) * normal
}

func buildOrthonormalBasis(_ normal: SIMD3<Float>) -> (tangent: SIMD3<Float>, bitangent: SIMD3<Float>) {
    let tangent: SIMD3<Float>
    if abs(normal.x) > 0.9 {
        tangent = normalize(SIMD3<Float>(0, 1, 0) - dot(SIMD3<Float>(0, 1, 0), normal) * normal)
    } else {
        tangent = normalize(SIMD3<Float>(1, 0, 0) - dot(SIMD3<Float>(1, 0, 0), normal) * normal)
    }
    let bitangent = cross(normal, tangent)
    return (tangent, bitangent)
}

// MARK: - GGX Sampling

func sampleGGX(viewDir: simd_float3, normal: simd_float3, roughness: Float) -> (direction: simd_float3, pdf: Float) {
    let u1 = randomFloat()
    let u2 = randomFloat()

    let alpha = roughness * roughness

    // Sample half vector in spherical coordinates
    let cosTheta = sqrt((1.0 - u1) / (1.0 + (alpha * alpha - 1.0) * u1))
    let sinTheta = sqrt(1.0 - cosTheta * cosTheta)
    let phi = 2.0 * Float.pi * u2

    // Half-vector in local tangent space
    let halfVecLocal = simd_float3(
        sinTheta * cos(phi),
        sinTheta * sin(phi),
        cosTheta
    )

    // Transform to world space
    let basis = buildOrthonormalBasis(normal)
    let halfVector = normalize(
        basis.tangent * halfVecLocal.x +
        basis.bitangent * halfVecLocal.y +
        normal * halfVecLocal.z
    )

    // Reflect view direction around half vector to get light direction
    let lightDirection = reflect(-viewDir, halfVector)

    // Calculate PDF
    let NoH = max(0.0, dot(normal, halfVector))
    let VoH = max(0.0, dot(viewDir, halfVector))
    let D = D_GGX(NoH: NoH, a: roughness)
    let pdf = (D * NoH) / (4.0 * VoH + 1e-6)

    return (direction: lightDirection, pdf: pdf)
}

// MARK: - BRDF Evaluation

func evaluateGGXBRDF(lightDir: SIMD3<Float>, viewDir: SIMD3<Float>, normal: SIMD3<Float>, material: Material) -> SIMD3<Float> {
    let halfVector = normalize(lightDir + viewDir)
    let NdotL = max(0.0, dot(normal, lightDir))
    let NdotV = max(0.0, dot(normal, viewDir))
    let NdotH = max(0.0, dot(normal, halfVector))
    let VdotH = max(0.0, dot(viewDir, halfVector))

    // Fresnel (Schlick approximation)
    let F0 = simd_mix(SIMD3<Float>(0.04, 0.04, 0.04), material.diffuse, simd_float3(repeating: material.metallic))
    let F = F0 + (SIMD3<Float>(1, 1, 1) - F0) * pow(1.0 - VdotH, 5.0)

    // Distribution (GGX)
    let alpha: Float = Float(material.roughness) * Float(material.roughness)
    let denom = NdotH * NdotH * (alpha * alpha - 1.0) + 1.0
    let D = alpha * alpha / (Float.pi * denom * denom)

    // Geometry function (simplified Smith)
    let k = (material.roughness + 1) * (material.roughness + 1) / 8
    let GL = NdotL / (NdotL * (1 - k) + k)
    let GV = NdotV / (NdotV * (1 - k) + k)
    let G = GL * GV

    // Specular BRDF
    let denominator = 4.0 * NdotL * NdotV + 1e-6
    return (D * G * F) / denominator
}

func calculateGGXPDF(_ halfVector: SIMD3<Float>, _ normal: SIMD3<Float>, _ viewDir: SIMD3<Float>, _ roughness: Float) -> Float {
    let alpha = roughness * roughness
    let NdotH = max(0.0, dot(normal, halfVector))
    let VdotH = max(0.0, dot(viewDir, halfVector))
    
    // GGX distribution
    let denom = NdotH * NdotH * (alpha * alpha - 1.0) + 1.0
    let D = alpha * alpha / (Float.pi * denom * denom)
    
    // PDF in half-vector space
    let pdfHalf = D * NdotH
    
    // Convert to light direction space (Jacobian = 1/(4*VdotH))
    return pdfHalf / (4.0 * VdotH)
}


// MARK: - Main Ray Generation Function

// func PBRShade(normal: simd_float3, material: Material, incomingRay: Ray) -> simd_float3 {
//     let viewDir = -normalize(incomingRay.direction)  // Direction towards camera

//     // Generate random numbers
//     let u1 = randomFloat()
//     let u2 = randomFloat()
    
//     // Sample half-vector according to GGX distribution
//     let halfVector = sampleGGXHalfVector(u1, u2, material.roughness, normal)
    
//     // Generate reflection ray
//     let lightDir = normalize(reflect(-viewDir, halfVector))
    
//     // Check if ray is above surface
//     guard dot(lightDir, normal) > 0 else {
//         return simd_float3(0, 0, 0) // Invalid direction
//     }
    
//     // Calculate PDF
//     let pdf = calculateGGXPDF(halfVector, normal, viewDir, material.roughness)
//     guard pdf > 0 else {
//         return simd_float3(0, 0, 0) // Invalid direction
//     }
    
//     // Calculate BRDF and weight
//     let brdf = evaluateGGXBRDF(lightDir: lightDir, viewDir: viewDir, normal: normal, material: material)
//     let NdotL = max(0.0, dot(normal, lightDir))

//     // let energyFactor = 1.0 / Float.pi // Energy conservation factor
//     let energyFactor: Float = 1.0
//     let weight = brdf * NdotL * energyFactor / max(pdf, 1e-6)
    
//     // return RaySample(direction: lightDir, pdf: pdf, weight: weight)
//     return weight
// }

func D_GGX(NoH: Float, a: Float) -> Float {
    let a2 = a * a
    let f = (NoH * a2 - NoH) * NoH + 1.0
    return a2 / (Float.pi * f * f)
}

func F_Schlick(LoH: Float, f0: simd_float3) -> simd_float3 {
    return f0 + (simd_float3(1,1,1) - f0) * pow(1.0 - LoH, 5.0)
}

func V_SmithGGXCorrelated(NoV: Float, NoL: Float, a: Float) -> Float {
    let a2 = a * a
    let GGXL = NoV * sqrt((-NoL * a2 + NoL) * NoL + a2)
    let GGXV = NoL * sqrt((-NoV * a2 + NoV) * NoV + a2)
    return 0.5 / (GGXV + GGXL)
}

func Fd_Lambert() -> Float {
    return 1.0 / Float.pi
}

func getUniformlyDistributedLightVector(u: Float, v: Float, normal: simd_float3) -> simd_float3 {
    // Generate uniform sampling in hemisphere
    let phi = 2.0 * Float.pi * u
    let cosTheta = v
    let sinTheta = sqrt(1.0 - cosTheta * cosTheta)
    
    // Create vector in local space
    let x = cos(phi) * sinTheta
    let y = sin(phi) * sinTheta
    let z = cosTheta
    
    // Convert to world space using the normal as up vector
    let (tangent, bitangent) = buildOrthonormalBasis(normal)
    
    // Transform from local to world space
    return normalize(
        tangent * x +
        bitangent * y +
        normal * z
    )
}
    
func calculateBRDFContribution(ray: Ray, point: simd_float3, normal: simd_float3, material: Material, l: simd_float3, lightValue: simd_float3) -> simd_float3 {
    let v = -normalize(ray.direction) // surface to view direction 
    let n = normal // surface normal

    let h = normalize(v + l) // half vector between view and light direction
    
    let NoV = abs(dot(n, v)) + 1e-5  // visbility used for fresnel + shadow
    let NoL = min(1.0, max(0.0, dot(n, l))) // shadowing + light attenuation (right now only from angle not distance)
    let NoH = min(1.0, max(0.0, dot(n, h)))  // used for microfacet distribution
    let LoH = min(1.0, max(0.0, dot(l, h)))  // used for fresnel

    let dielectricF0 = simd_float3(repeating: 0.04) // Default F0 for dielectric materials
    let f0 = simd_mix(dielectricF0, material.diffuse, simd_float3(repeating: material.metallic))

    let D = D_GGX(NoH: NoH, a: material.roughness)
    let F = F_Schlick(LoH: LoH, f0: f0)
    let G = V_SmithGGXCorrelated(NoV: NoV, NoL: NoL, a: material.roughness)

    let Fr = (D * G) * F / (4.0 * NoV * NoL + 1e-7) 

    // Diffuse BRDF
    let energyCompensation = simd_float3(repeating: 1.0) - F  // Amount of light not reflected
    let Fd: simd_float3 = material.diffuse * (Fd_Lambert()) * energyCompensation * (1.0 - material.metallic)
    
    // Combine both terms and apply light properties
    let BRDF = (Fd + Fr)
    
    let finalColor = BRDF * lightValue * NoL

    return finalColor
}

func reinhartToneMapping(_ value: simd_float3) -> simd_float3 {
    var finalColor = value / (value + simd_float3(1, 1, 1)) // Simple tone mapping to avoid overexposure
    finalColor = clamp(pow(value, simd_float3(repeating: 1.0 / 2.2)), min: 0, max: 1) // Gamma correction
    return finalColor
}

func khronosToneMapping(color: simd_float3) -> simd_float3 {
    let startCompression: Float = 0.8 - 0.04
    let desaturation: Float = 0.15

    let x = min(color.x, min(color.y, color.z))
    let offset = x < 0.08 ? x - 6.25 * x * x : 0.04
    var offsetColor = color - simd_float3(repeating: offset)
    let peak = max(color.x, max(color.y, color.z))
    if peak < startCompression {
        return offsetColor
    }
    let d = 1 - startCompression
    let newPeak = 1 - d * d / (peak + d - startCompression)
    offsetColor *= newPeak / peak
    let g = 1 - 1 / (desaturation * (peak - newPeak) + 1)
    return mix(offsetColor, newPeak * simd_float3(repeating: 1.0), t: g)
}

func sampleSphereLight(light: SphereLight, point: simd_float3) -> (direction: simd_float3, pdf: Float, radiance: simd_float3) {
    // Sample a random point on the light sphere surface
    let u1 = randomFloat()
    let u2 = randomFloat()

    // Uniform sampling on sphere surface
    let cosTheta = 1.0 - 2.0 * u1
    let sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta))
    let phi = 2.0 * Float.pi * u2

    // Point on light sphere in local coordinates
    let localPoint = simd_float3(
        sinTheta * cos(phi),
        sinTheta * sin(phi),
        cosTheta
    )

    // Transform to world space
    let lightSurfacePoint = light.center + localPoint * light.radius

    // Direction from surface point to light
    let lightDirection = lightSurfacePoint - point
    let distance = simd_length(lightDirection)
    let normalizedDirection = lightDirection / distance

    // PDF calculation (solid angle)
    let lightSurfaceArea = 4.0 * Float.pi * light.radius * light.radius
    let cosLightNormal = dot(-normalizedDirection, localPoint) // Angle at light surface

    // Convert area PDF to solid angle PDF
    let pdf = (distance * distance) / (lightSurfaceArea * max(cosLightNormal, 1e-6))

    return (direction: normalizedDirection, pdf: pdf, radiance: light.emittedRadiance)
}