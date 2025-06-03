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

func sampleGGXHalfVector(_ u1: Float, _ u2: Float, _ roughness: Float, _ normal: SIMD3<Float>) -> SIMD3<Float> {
    let alpha = roughness * roughness
    
    // Sample in spherical coordinates
    let cosTheta = sqrt((1.0 - u1) / (1.0 + (alpha * alpha - 1.0) * u1))
    let sinTheta = sqrt(1.0 - cosTheta * cosTheta)
    let phi = 2.0 * Float.pi * u2
    
    // Half-vector in local tangent space
    let halfVecLocal = SIMD3<Float>(
        sinTheta * cos(phi),
        sinTheta * sin(phi),
        cosTheta
    )
    
    // Transform to world space
    let basis = buildOrthonormalBasis(normal)
    return normalize(
        basis.tangent * halfVecLocal.x +
        basis.bitangent * halfVecLocal.y +
        normal * halfVecLocal.z
    )
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

func PBRShade(normal: simd_float3, material: Material, incomingRay: Ray) -> simd_float3 {
    let viewDir = -normalize(incomingRay.direction)  // Direction towards camera

    // Generate random numbers
    let u1 = randomFloat()
    let u2 = randomFloat()
    
    // Sample half-vector according to GGX distribution
    let halfVector = sampleGGXHalfVector(u1, u2, material.roughness, normal)
    
    // Generate reflection ray
    let lightDir = normalize(reflect(-viewDir, halfVector))
    
    // Check if ray is above surface
    guard dot(lightDir, normal) > 0 else {
        return simd_float3(0, 0, 0) // Invalid direction
    }
    
    // Calculate PDF
    let pdf = calculateGGXPDF(halfVector, normal, viewDir, material.roughness)
    guard pdf > 0 else {
        return simd_float3(0, 0, 0) // Invalid direction
    }
    
    // Calculate BRDF and weight
    let brdf = evaluateGGXBRDF(lightDir: lightDir, viewDir: viewDir, normal: normal, material: material)
    let NdotL = max(0.0, dot(normal, lightDir))

    // let energyFactor = 1.0 / Float.pi // Energy conservation factor
    let energyFactor: Float = 1.0
    let weight = brdf * NdotL * energyFactor / max(pdf, 1e-6)
    
    // return RaySample(direction: lightDir, pdf: pdf, weight: weight)
    return weight
}

func luminanceToRGB(_ luminance: simd_float3, exposure: Float = 1.0) -> simd_float3 {
        // Apply exposure compensation
        let exposedColor = luminance * exposure
        
        // ACES tone mapping parameters
        let a: Float = 2.51
        let b: Float = 0.03
        let c: Float = 2.43
        let d: Float = 0.59
        let e: Float = 0.14
        
        // Apply ACES filmic tone mapping curve to each channel
        let ax = (a * exposedColor.x + b)
        let ay = (a * exposedColor.y + b)
        let az = (a * exposedColor.z + b)
        let cx = (c * exposedColor.x + d)
        let cy = (c * exposedColor.y + d)
        let cz = (c * exposedColor.z + d)


        let toneMapped = simd_float3(
            (exposedColor.x * ax) / (exposedColor.x * cx + e),
            (exposedColor.y * ay) / (exposedColor.y * cy + e),
            (exposedColor.z * az) / (exposedColor.z * cz + e)
        )
        
        // Clamp values to [0,1] range
        return simd_clamp(toneMapped, simd_float3(0,0,0), simd_float3(1,1,1))
}

func D_GGX(NoH: Float, a: Float) -> Float {
    let a2 = a * a
    let f = (NoH * a2 - NoH) * NoH + 1.0
    return a2 / (Float.pi * f * f)
}

func F_Schlick(LoH: Float, f0: simd_float3) -> simd_float3 {
    let reflected = f0 + (simd_float3(1,1,1) - f0)
    return  reflected * pow(1.0 - LoH, 5.0)
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
