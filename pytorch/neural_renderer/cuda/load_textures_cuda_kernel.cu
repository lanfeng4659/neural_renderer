#include <ATen/ATen.h>

#include <cuda.h>
#include <cuda_runtime.h>

namespace {
template <typename scalar_t>
__global__ void load_textures_cuda_kernel(
    const scalar_t* __restrict__ image,
    const scalar_t* __restrict__ faces,
    const int32_t* __restrict__ is_update,
    scalar_t* __restrict__ textures, 
    size_t texture_size,
    size_t image_height,
    size_t image_width) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= texture_size / 3) {
      return;
  }
  const int ts = texture_size;
  const int fn = i / (ts * ts * ts);
  scalar_t dim0 = ((i / (ts * ts)) % ts) / (ts - 1.) ;
  scalar_t dim1 = ((i / ts) % ts) / (ts - 1.);
  scalar_t dim2 = (i % ts) / (ts - 1.);
  if (1 < dim0 + dim1 + dim2) {
      float sum = dim0 + dim1 + dim2;
      dim0 /= sum;
      dim1 /= sum;
      dim2 /= sum;
  }
  const scalar_t* face = &faces[fn * 3 * 2];
  scalar_t* texture = &textures[i * 3];
  if (is_update[fn] == 0) return;
  
  const scalar_t pos_x = (
      (face[2 * 0 + 0] * dim0 + face[2 * 1 + 0] * dim1 + face[2 * 2 + 0] * dim2) * (image_width - 1));
  const scalar_t pos_y = (
      (face[2 * 0 + 1] * dim0 + face[2 * 1 + 1] * dim1 + face[2 * 2 + 1] * dim2) * (image_height - 1));
  if (1) {
      /* bilinear sampling */
      const scalar_t weight_x1 = pos_x - (int)pos_x;
      const scalar_t weight_x0 = 1 - weight_x1;
      const scalar_t weight_y1 = pos_y - (int)pos_y;
      const scalar_t weight_y0 = 1 - weight_y1;
      for (int k = 0; k < 3; k++) {
          scalar_t c = 0;
          c += image[((int)pos_y * image_width + (int)pos_x) * 3 + k] * (weight_x0 * weight_y0);
          c += image[((int)(pos_y + 1) * image_width + (int)pos_x) * 3 + k] * (weight_x0 * weight_y1);
          c += image[((int)pos_y * image_width + ((int)pos_x) + 1) * 3 + k] * (weight_x1 * weight_y0);
          c += image[((int)(pos_y + 1)* image_width + ((int)pos_x) + 1) * 3 + k] * (weight_x1 * weight_y1);
          texture[k] = c;
      }
  } else {
      /* nearest neighbor */
      const int pos_xi = round(pos_x);
      const int pos_yi = round(pos_y);
      for (int k = 0; k < 3; k++) {
          texture[k] = image[(pos_yi * image_width + pos_xi) * 3 + k];
      }
  }
}
}

at::Tensor load_textures_cuda(
        at::Tensor image,
        at::Tensor faces,
        at::Tensor is_update,
        at::Tensor textures) {
    const auto texture_size = textures.size(1);
    const auto image_height = image.size(0);
    const auto image_width = image.size(1);
    
    const int threads = 1024;
    const int blocks = (texture_size / 3 - 1) / threads + 1;

    AT_DISPATCH_FLOATING_TYPES(image.type(), "load_textures_cuda", ([&] {
      load_textures_cuda_kernel<scalar_t><<<blocks, threads>>>(
          image.data<scalar_t>(),
          faces.data<scalar_t>(),
          is_update.data<int32_t>(),
          textures.data<scalar_t>(),
          texture_size,
          image_height,
          image_width);
      }));

    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) 
            printf("Error in load_textures: %s\n", cudaGetErrorString(err));
    return textures;
}
