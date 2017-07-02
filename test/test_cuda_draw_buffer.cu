#include "gtest/gtest.h"
#include "macros.h"
#include "triangle.h"
#include "ray.h"


#include <cuda.h>
#include <cuda_gl_interop.h>
#include <cuda_runtime.h>
#include <GLFW/glfw3.h>
#include <gsl/gsl>
#include <iostream>
#include <thrust/device_free.h>
#include <thrust/device_malloc.h>
#include <thrust/device_new.h>
#include <thrust/device_vector.h>
#include <thrust/execution_policy.h>
#include <thrust/fill.h>
#include <utility>

static void quit_with_q(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if(key == GLFW_KEY_Q && action == GLFW_PRESS)
        glfwSetWindowShouldClose(window, GLFW_TRUE);
}


TEST(cuda_draw, window_and_context_creation) {
    auto InitVal = glfwInit();
    ASSERT_NE(InitVal, 0) << "Could not initialize GLFW";

    gsl::owner<GLFWwindow*> Window = glfwCreateWindow(640, 480, "Test CUDA drawing", nullptr, nullptr);
    ASSERT_NE(Window, nullptr) << "Window not created";

    OUT << "Close window and test with q" << std::endl;
    
    // window shall be closed when q is pressed
    glfwSetKeyCallback(Window, quit_with_q);

    // opengl context for drawing
    glfwMakeContextCurrent(Window);

    while(!glfwWindowShouldClose(Window)) {
        glfwPollEvents();
    }

    glfwDestroyWindow(Window);
    glfwTerminate();
}

/// https://stackoverflow.com/questions/19244191/cuda-opengl-interop-draw-to-opengl-texture-with-cuda
std::pair<GLuint, cudaGraphicsResource_t> initialize_texture() {
    GLuint Texture;
    cudaGraphicsResource_t CudaResource;

    glEnable(GL_TEXTURE_2D);
    glGenTextures(1, &Texture);

    glBindTexture(GL_TEXTURE_2D, Texture);
    { // beauty stuff for opengl, maybe skip?
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 640, 480, 0, GL_RGBA, GL_UNSIGNED_BYTE, 
                     nullptr);
    }
    glBindTexture(GL_TEXTURE_2D, 0);

    /*auto E = */cudaGraphicsGLRegisterImage(&CudaResource, Texture, GL_TEXTURE_2D, 
                                             cudaGraphicsRegisterFlagsWriteDiscard);

    // Memory mapping
    cudaGraphicsMapResources(1, &CudaResource); 

    return std::make_pair(Texture, CudaResource);
}

/// Plain render the texture to the screen, with no transformation or anything
void render_opengl(GLuint Texture) {
    glBindTexture(GL_TEXTURE_2D, Texture);
    {
        glBegin(GL_QUADS);
        {
			glTexCoord2f(0.0f, 0.0f); glVertex2f(-1.0f, -1.0f);
            glTexCoord2f(1.0f, 0.0f); glVertex2f(+1.0f, -1.0f);
            glTexCoord2f(1.0f, 1.0f); glVertex2f(+1.0f, +1.0f);
            glTexCoord2f(0.0f, 1.0f); glVertex2f(-1.0f, +1.0f); 
        }
        glEnd();
    }
    glBindTexture(GL_TEXTURE_2D, 0);
    glFinish();
}

__global__ void grayKernel(cudaSurfaceObject_t Surface, int width, int height, float t)
{
    auto x = blockIdx.x * blockDim.x + threadIdx.x;
    auto y = blockIdx.y * blockDim.y + threadIdx.y;

    if(x < width && y < height)
    {
        uchar4 Color;
        char new_t = t;
        Color.x = x - new_t;
        Color.y = y + new_t;
        Color.z = new_t;
        Color.w = 255;
        surf2Dwrite(Color, Surface, x * 4, y);
    }
}

void invokeRenderingKernel(const cudaSurfaceObject_t& Surface, float t)
{
    //std::cout << "Rendering new image " << char{t} << std::endl;
    dim3 dimBlock(32,32);
    dim3 dimGrid((640 + dimBlock.x) / dimBlock.x,
                 (480 + dimBlock.y) / dimBlock.y);
    grayKernel<<<dimGrid, dimBlock>>>(Surface, 640, 480, t);
}

/// Write pixel data with cuda.
void render_cuda(cudaGraphicsResource_t& GraphicsResource, float t) {
    // Stuff
    cudaArray_t CudaArray;
    cudaGraphicsSubResourceGetMappedArray(&CudaArray, GraphicsResource, 0, 0);

    // More Stuff
    cudaResourceDesc CudaArrayResourceDesc;
    CudaArrayResourceDesc.resType = cudaResourceTypeArray;
    CudaArrayResourceDesc.res.array.array = CudaArray;

    // Surface creation
    cudaSurfaceObject_t CudaSurfaceObject;
    cudaCreateSurfaceObject(&CudaSurfaceObject, &CudaArrayResourceDesc); 

    // Rendering
    invokeRenderingKernel(CudaSurfaceObject, t);

    // raytracing should be something like that:
    // thrust::for_each(thrust::device, PrimaryRays.begin(), PrimaryRays.end(),
    // CUCALL [&CudaSurfaceObject,&Geometry](const ray& R) {
    //    // Determine all Intersections for that ray.
    //    thrust::device_vector<intersect> Hits;
    //    thrust::for_each(Geometry.begin(), Geometry.end(),
    //        [R,&Hits] (const triangle& T) {
    //            auto Test = R.intersects(T);
    //            if(Test.first) { Hits.push_back(Test.second); }
    //    });
    //    if(Hits.empty()) { 
    //        surf2Dwrite(BGColor, CudaSurfaceObject, R.u * 4, R.v);
    //    } 
    //    else {
    //        surf2Dwrite(FGColor, CudaSurfaceObject, R.u * 4, R.v);
    //    }
    // });


    //         // Determine the closest intersection of all Rays.
    //         auto Closest = *thrust::min_element(thrust::device, Hits.begin(), Hits.end(),
    //                         [](const intersect& I1, const intersect& I2) 
    //                         { return I1.deepth < I2.depth; });
    //         }
    //     });

    // Lulu
    cudaDestroySurfaceObject(CudaSurfaceObject);
}

TEST(cuda_draw, basic_drawing) {
    auto InitVal = glfwInit();
    ASSERT_NE(InitVal, 0) << "Could not initialize GLFW";

    gsl::owner<GLFWwindow*> Window = glfwCreateWindow(640, 480, "Test CUDA drawing", 
                                                      nullptr, nullptr);
    ASSERT_NE(Window, nullptr) << "Window not created";

    OUT << "Close window and test with q" << std::endl;
    
    // window shall be closed when q is pressed
    glfwSetKeyCallback(Window, quit_with_q);

    // opengl context for drawing
    glfwMakeContextCurrent(Window);

    // register a glTexture, that can be filled black ...
    GLuint Texture;
    cudaGraphicsResource_t GraphicsResource;
    std::tie(Texture, GraphicsResource) = initialize_texture();
    ASSERT_NE(Texture, 0) << "Could not create gl buffer";

    float t = 0.f;
    while(!glfwWindowShouldClose(Window)) {
        t += 0.1f;
        render_cuda(GraphicsResource, t);
        // Render that texture with OpenGL
        // https://stackoverflow.com/questions/19244191/cuda-opengl-interop-draw-to-opengl-texture-with-cuda
        render_opengl(Texture);

        glfwSwapBuffers(Window);
        glfwPollEvents();
    }

    // Clean up the cuda memory mapping
    cudaGraphicsUnmapResources(1, &GraphicsResource);
    //ASSERT_EQ(e, cudaSuccess) << "Could not unmap the resource";

    glfwDestroyWindow(Window);
    glfwTerminate();
}

/// Write pixel data with cuda.
void render_cuda2(cudaSurfaceObject_t& Surface, float t) {
    // Rendering
    invokeRenderingKernel(Surface, t);
}

TEST(cuda_draw, drawing_less_surfaces) {
    auto InitVal = glfwInit();
    ASSERT_NE(InitVal, 0) << "Could not initialize GLFW";

    gsl::owner<GLFWwindow*> Window = glfwCreateWindow(640, 480, "Test CUDA drawing", 
                                                      nullptr, nullptr);
    ASSERT_NE(Window, nullptr) << "Window not created";

    OUT << "Close window and test with q" << std::endl;
    
    // window shall be closed when q is pressed
    glfwSetKeyCallback(Window, quit_with_q);

    // opengl context for drawing
    glfwMakeContextCurrent(Window);

    // register a glTexture, that can be filled black ...
    GLuint Texture;
    cudaGraphicsResource_t GraphicsResource;
    std::tie(Texture, GraphicsResource) = initialize_texture();
    ASSERT_NE(Texture, 0) << "Could not create gl buffer";

    // Maybe surface creation must be done only once?
    // Stuff
    cudaArray_t CudaArray;
    cudaGraphicsSubResourceGetMappedArray(&CudaArray, GraphicsResource, 0, 0);

    // More Stuff
    cudaResourceDesc CudaArrayResourceDesc;
    CudaArrayResourceDesc.resType = cudaResourceTypeArray;
    CudaArrayResourceDesc.res.array.array = CudaArray;

    // Surface creation
    cudaSurfaceObject_t CudaSurfaceObject;
    cudaCreateSurfaceObject(&CudaSurfaceObject, &CudaArrayResourceDesc); 

    float t = 0.f;
    while(!glfwWindowShouldClose(Window)) {
        t += 0.1f;
        render_cuda2(CudaSurfaceObject, t);
        render_opengl(Texture);

        glfwSwapBuffers(Window);
        glfwPollEvents();
    }
    cudaDestroySurfaceObject(CudaSurfaceObject);

    // Clean up the cuda memory mapping
    cudaGraphicsUnmapResources(1, &GraphicsResource);
    //ASSERT_EQ(e, cudaSuccess) << "Could not unmap the resource";

    glfwDestroyWindow(Window);
    glfwTerminate();
}


__global__ void trace_kernel(cudaSurfaceObject_t Surface, triangle* T, int Width, int Height) {
    const auto x = blockIdx.x * blockDim.x + threadIdx.x;
    const auto y = blockIdx.y * blockDim.y + threadIdx.y;

    const float focal_length = 2.f;

    if(x < Width && y < Height)
    {
        ray R;
        R.origin    = coord{0., 0., 0.};
        float DX = 2.f / ((float) Width  - 1);
        float DY = 2.f / ((float) Height - 1);
        R.direction = coord{x * DX - 1.f, y * DY - 1.f, focal_length};

        uchar4 FGColor;
        FGColor.x = 255;
        FGColor.y = 255;
        FGColor.z = 255;
        FGColor.w = 255;

        uchar4 BGColor;
        BGColor.x = 0;
        BGColor.y = 0;
        BGColor.z = 0;
        BGColor.w = 255;
        
        const auto Traced = R.intersects(*T);

        if(Traced.first) {
            surf2Dwrite(FGColor, Surface, x * 4, y);
        }
        else {
            surf2Dwrite(BGColor, Surface, x * 4, y);
        }
    }
}

void raytrace_cuda(cudaSurfaceObject_t& Surface, triangle* T) {
    dim3 dimBlock(32,32);
    dim3 dimGrid((640 + dimBlock.x) / dimBlock.x,
                 (480 + dimBlock.y) / dimBlock.y);
    trace_kernel<<<dimGrid, dimBlock>>>(Surface, T, 640, 480);
}

TEST(cuda_draw, drawing_traced_triangle) 
{
    auto InitVal = glfwInit();
    ASSERT_NE(InitVal, 0) << "Could not initialize GLFW";

    gsl::owner<GLFWwindow*> Window = glfwCreateWindow(640, 480, "Test CUDA triangle", 
                                                      nullptr, nullptr);
    ASSERT_NE(Window, nullptr) << "Window not created";

    OUT << "Close window and test with q" << std::endl;
    
    // window shall be closed when q is pressed
    glfwSetKeyCallback(Window, quit_with_q);

    // opengl context for drawing
    glfwMakeContextCurrent(Window);
    {
        // register a glTexture, that can be filled black ...
        GLuint Texture;
        cudaGraphicsResource_t GraphicsResource;
        std::tie(Texture, GraphicsResource) = initialize_texture();
        ASSERT_NE(Texture, 0) << "Could not create gl buffer";

        // Maybe surface creation must be done only once?
        // Stuff
        cudaArray_t CudaArray;
        cudaGraphicsSubResourceGetMappedArray(&CudaArray, GraphicsResource, 0, 0);

        // More Stuff
        cudaResourceDesc CudaArrayResourceDesc;
        CudaArrayResourceDesc.resType = cudaResourceTypeArray;
        CudaArrayResourceDesc.res.array.array = CudaArray;

        // Surface creation
        cudaSurfaceObject_t CudaSurfaceObject;
        cudaCreateSurfaceObject(&CudaSurfaceObject, &CudaArrayResourceDesc); 
        // Clean up the cuda memory mapping
        auto __ = gsl::finally([&CudaSurfaceObject, &GraphicsResource]() 
                    {
                        cudaDestroySurfaceObject(CudaSurfaceObject);
                        cudaGraphicsUnmapResources(1, &GraphicsResource);
                    });

        // Create the Triangle and Coordinates on the device
        thrust::device_vector<coord> Vertices(3);
        //Vertices[0] = {.5f,-1,1}; 
        //Vertices[1] = {-1,.5f,1};
        //Vertices[2] = {1,1,1};
        Vertices[0] = {0,-1,1}; 
        Vertices[1] = {-1,1,1};
        Vertices[2] = {1,1,1};

        const thrust::device_ptr<coord> P0 = &Vertices[0];
        const thrust::device_ptr<coord> P1 = &Vertices[1];
        const thrust::device_ptr<coord> P2 = &Vertices[2];

        const auto triangle_void = thrust::device_malloc(sizeof(triangle));
        auto _ = gsl::finally([&triangle_void]() { thrust::device_free(triangle_void); });
        const auto triangle_ptr = thrust::device_new(triangle_void, 
                                                     triangle{P0.get(), P1.get(), P2.get()});

        while(!glfwWindowShouldClose(Window)) {
            raytrace_cuda(CudaSurfaceObject, triangle_ptr.get());
            render_opengl(Texture);

            glfwSwapBuffers(Window);
            glfwPollEvents();
        }

    }

    glfwDestroyWindow(Window);
    glfwTerminate();
}

int main(int argc, char** argv)
{
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
