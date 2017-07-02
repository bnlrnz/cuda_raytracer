#include "gtest/gtest.h"
#include <cuda.h>
#include <cuda_gl_interop.h>
#include <cuda_runtime.h>

#include "visualization.h"


TEST(visualization, basic_starting)
{
    visualization vis(640, 480);
}


int main(int argc, char** argv)
{
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}