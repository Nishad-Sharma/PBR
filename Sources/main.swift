//
//  main.swift
//  raytrace
//
//  Created by Nishad Sharma on 2/6/2025.
//

import Foundation
import simd

let sun = SphereLight(center: simd_float3(0, 10, 0), radius: 1.0, color: simd_float3(1, 1, 1), intensity: 1000.0)
let camera = Camera(position: simd_float3(0, 0, 5), direction: simd_float3(0, 0, -1), horizontalFov: Double.pi / 4.0, resolution: simd_int2(800, 600))
let spheres = [
    Sphere(center: simd_float3(0, 0, 0), radius: 1.0, material: Material(color: simd_float3(1, 0, 0), metallic: 0.5, roughness: 0.1)),
    Sphere(center: simd_float3(-2, 0, 0), radius: 1.0, material: Material(color: simd_float3(0, 1, 0), metallic: 0.5, roughness: 0.1)),
    Sphere(center: simd_float3(1, 0, 0), radius: 1.0, material: Material(color: simd_float3(0, 0, 1), metallic: 0.5, roughness: 0.1))
]
let scene = Scene(spheres: spheres, light: sun, camera: camera)
scene.render()

class Scene {
    var spheres: [Sphere] = []
    var light: SphereLight
    var camera: Camera
    var ambientLight: simd_float3 = simd_float3(0.1, 0.1, 0.1) // Ambient light color

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
                return .hit(point: hitPoint, color: sphere.material.color)
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
            case .hit(let point, _):
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
                      
                case .hit(let point, let color):
                    // get distance between light and intersection 
                    let distanceAttenuation = 1 / simd_length(point - light.center)


                    let color: simd_float3 = color 
                    let attenuatedColor = color * distanceAttenuation
                    let pixelOffset = index * 4
                    pixels[pixelOffset + 0] = UInt8(attenuatedColor.x * 255)  // R
                    pixels[pixelOffset + 1] = UInt8(attenuatedColor.y * 255)  // G
                    pixels[pixelOffset + 2] = UInt8(attenuatedColor.z * 255)  // B
                    pixels[pixelOffset + 3] = 255                    // A
                }
        }
        savePixelArrayToImage(pixels: pixels, width: width, height: height, fileName: "/Users/nishadsharma/Documents/raytrace/gradient.png")
    }

}

enum Intersection {
    case hit(point: simd_float3, color: simd_float3)
    case miss
}

struct Sphere {
    var center: simd_float3
    var radius: Double
    var material: Material
}

struct SphereLight {
    var center: simd_float3
    var radius: Double
    var color: simd_float3
    var intensity: Double //lumens
}

struct Material {
    var color: simd_float3
    var metallic: Double
    var roughness: Double
}

struct Camera {
    var position: simd_float3
    var direction: simd_float3
    var horizontalFov: Double // field of view in radians
    var resolution: simd_int2

    func generateRays() -> [Ray] {
        var rays: [Ray] = []
        let aspectRatio = Double(resolution.x) / Double(resolution.y)
        let halfWidth = tan(horizontalFov / 2.0)
        let halfHeight = halfWidth / aspectRatio
        
        for y in 0..<resolution.y {
            for x in 0..<resolution.x {
                let u = (Double(x) / Double(resolution.x)) * 2.0 - 1.0
                let v = (Double(y) / Double(resolution.y)) * 2.0 - 1.0
                
                let direction = simd_float3(
                    Float(u * halfWidth),
                    Float(v * halfHeight),
                    -1.0 // assuming camera looks down the negative z-axis
                )
                
                rays.append(Ray(origin: position, direction: simd_normalize(direction)))
            }
        }
        return rays
    }

}

struct Ray {
    var origin: simd_float3
    var direction: simd_float3    
}
