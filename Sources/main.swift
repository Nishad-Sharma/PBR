//
//  main.swift
//  raytrace
//
//  Created by Nishad Sharma on 2/6/2025.
//

import Foundation
import simd

let sun = SphereLight(center: simd_float3(0, 10, 0), radius: 10.0, color: simd_float3(1, 1, 1), intensity: 30000.0)
let direction = simd_normalize(simd_float3(0, 0, 0) - simd_float3(13, 2, 3))
let camera = Camera(position: simd_float3(13, 2, 3), direction: direction, horizontalFov: Float.pi / 4.0, resolution: simd_int2(600, 400))
let spheres = [
    Sphere(center: simd_float3(4, 1, 0), radius: 1.0, material: Material(diffuse: simd_float3(0, 0, 1), metallic: 1, roughness: 0.01)), //front 
    Sphere(center: simd_float3(0, 1, 0), radius: 1.0, material: Material(diffuse: simd_float3(1, 0, 0), metallic: 0, roughness: 0.1)), //middle
    Sphere(center: simd_float3(-4, 1, 0), radius: 1.0, material: Material(diffuse: simd_float3(0, 1, 0), metallic: 0, roughness: 0.9)), //back
    Sphere(center: simd_float3(0, -1000, 0), radius: 1000.0, material: Material(diffuse: simd_float3(0, 1, 1), metallic: 0, roughness: 1))
]

let scene = Scene(spheres: spheres, light: sun, camera: camera)
scene.render()

class Scene {
    var spheres: [Sphere] = []
    var light: SphereLight
    var camera: Camera
    var ambientLight: simd_float3 = simd_float3(0.53, 0.81, 0.92) // Ambient light color

    init(spheres: [Sphere], light: SphereLight, camera: Camera) {
        self.spheres = spheres
        self.light = light
        self.camera = camera
    }

    func intersect(ray: Ray, sphere: Sphere) -> Intersection {
        let oc = ray.origin - sphere.center
        let a = simd_dot(ray.direction, ray.direction)
        let b = 2.0 * simd_dot(oc, ray.direction)
        let c = simd_dot(oc, oc) - Float(sphere.radius * sphere.radius)
        let discriminant = b * b - 4 * a * c

        if discriminant > 0 {
            let t1 = (-b - sqrt(discriminant)) / (2.0 * a)
            let t2 = (-b + sqrt(discriminant)) / (2.0 * a)
            if t1 > 0 || t2 > 0 {
                let hitPoint = ray.origin + ray.direction * min(t1, t2)
                return .hit(point: hitPoint, color: sphere.material.diffuse, material: sphere.material, ray: ray, normal: simd_normalize(hitPoint - sphere.center))
            }
        }
        return .miss
    }


    func generateRays(intersection: Intersection) -> [Ray] {
        return []
    }

    func getClosestIntersection(ray: Ray) -> Intersection {
        var closestIntersection: Intersection = .miss
        var closestDistance: Float = Float.infinity

        for sphere in spheres {
            let intersection = intersect(ray: ray, sphere: sphere)
            switch intersection {
            case .hit(let point, _, _, _, _):
                let distance = simd_length(point - ray.origin)
                if distance < closestDistance {
                    closestDistance = distance
                    closestIntersection = intersection
                }
            case .miss:
                continue
            }
        }
        return closestIntersection
    }

    func render() {
        let width = Int(camera.resolution.x)
        let height = Int(camera.resolution.y)
        let pixelCount = width * height
        // Pre-allocate pixels array with black transparent pixels
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)

        let rays = camera.generateRays()
        for (index, ray) in rays.enumerated() {
            let intersection = getClosestIntersection(ray: ray)
            switch intersection {
                case .miss:
                    let color = ambientLight
                    let pixelOffset = index * 4
                    pixels[pixelOffset + 0] = UInt8(color.x * 255)  // R
                    pixels[pixelOffset + 1] = UInt8(color.y * 255)  // G
                    pixels[pixelOffset + 2] = UInt8(color.z * 255)  // B
                    pixels[pixelOffset + 3] = 255        
                case .hit(let point, _, let material, let ray, let normal):

                    let v = -normalize(ray.direction) // surface to view direction 
                    let n = normal // surface normal
                    let l = normalize(light.center - point) // direction to light
                    let h = normalize(v + l) // half vector between view and light direction
                    
                    let NoV = abs(dot(n, v)) + 1e-5  // visbility used for fresnel + shadow
                    let NoL = min(1.0, max(0.0, dot(n, l))) // shadowing + light attenuation (right now only from angle not distance)
                    let NoH = min(1.0, max(0.0, dot(n, h)))  // used for microfacet distribution
                    let LoH = min(1.0, max(0.0, dot(l, h)))  // used for fresnel

                    let D = D_GGX(NoH: NoH, a: material.roughness)
                    let F = F_Schlick(LoH: LoH, f0: material.diffuse)
                    let G = V_SmithGGXCorrelated(NoV: NoV, NoL: NoL, a: material.roughness)

                    let Fr = (D * G) * F
        
                    // Diffuse BRDF
                    let energyCompensation = 1.0 - F  // Amount of light not reflected
                    let Fd: simd_float3 = (Fd_Lambert()) * material.diffuse  * energyCompensation
                    
                    // Combine both terms and apply light properties
                    let BRDF = (Fd + Fr) * NoL
                    
                    // Apply light intensity with inverse square falloff
                    let distanceToLight = simd_length(light.center - point)
                    let attenuation = light.intensity / (4.0 * Float.pi * distanceToLight * distanceToLight)
                    
                    let finalColor = BRDF * light.color * attenuation
                    // let color = finalColor

                    // let exposure: Float = 0.1 // Adjust this value based on your scene's brightness
                    // let color = luminanceToRGB(finalColor, exposure: exposure)
                    var color = finalColor / (finalColor + simd_float3(1, 1, 1)) // Simple tone mapping to avoid overexposure
                    color = clamp(pow(color, simd_float3(repeating: 1.0 / 2.2)), min: 0, max: 1) // Gamma correction

                    let pixelOffset = index * 4
                    pixels[pixelOffset + 0] = UInt8(color.x * 255)  // R
                    pixels[pixelOffset + 1] = UInt8(color.y * 255)  // G
                    pixels[pixelOffset + 2] = UInt8(color.z * 255)  // B
                    pixels[pixelOffset + 3] = 255                   // A
                }
        }
        savePixelArrayToImage(pixels: pixels, width: width, height: height, fileName: "/Users/nishadsharma/Documents/raytrace/gradient.png")
    }

}

enum Intersection {
    case hit(point: simd_float3, color: simd_float3, material: Material, ray: Ray, normal: simd_float3)
    case miss
}

struct Sphere {
    var center: simd_float3
    var radius: Float
    var material: Material
}

struct SphereLight {
    var center: simd_float3
    var radius: Float
    var color: simd_float3
    var intensity: Float //lumens
}

struct Material {
    var diffuse: simd_float3
    var metallic: Float
    var roughness: Float
}

struct Camera {
    var position: simd_float3
    var direction: simd_float3
    var horizontalFov: Float // field of view in radians
    var resolution: simd_int2
    var up: simd_float3 = simd_float3(0, 1, 0) // assuming camera's up vector is positive y-axis

    func generateRays() -> [Ray] {
        var rays: [Ray] = []
        let aspectRatio = Float(resolution.x / resolution.y)
        let halfWidth = tan(horizontalFov / 2.0)
        let halfHeight = halfWidth / aspectRatio
        
        // Create camera coordinate system
        let w = -simd_normalize(direction)  // Forward vector
        let u = simd_normalize(simd_cross(up, w))  // Right vector
        let v = simd_normalize(simd_cross(w, u))  // Up vector (normalized)
        
        for y in 0..<resolution.y {
            for x in 0..<resolution.x {
                let s = (Float(x) / Float(resolution.x)) * 2.0 - 1.0
                // Flip the t coordinate by negating it
                let t = -((Float(y) / Float(resolution.y)) * 2.0 - 1.0)
                
                // Calculate ray direction in camera space
                let dir = simd_float3(
                    Float(s * halfWidth) * u +
                    Float(t * halfHeight) * v -
                    w
                )
                
                rays.append(Ray(origin: position, direction: simd_normalize(dir)))
            }
        }
        return rays
    }
}

struct Ray {
    var origin: simd_float3
    var direction: simd_float3    
}
