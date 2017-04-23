// Testcase to load an object file

#include "gtest/gtest.h"
#include <iostream>


#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
TEST(ad_san, test_out_of_bounds) {
    char some_array[10];
    some_array[9] = 0;

#if defined (__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warray-bounds"
#endif
    some_array[15] = 'c';
#if defined (__clang__)
#pragma clang diagnostic pop
#endif
}
#pragma GCC diagnostic pop

int main(int argc, char** argv)
{
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
