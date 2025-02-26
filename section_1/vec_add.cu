﻿
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>
#include <iostream>
#include <random>
#include <assert.h>
#include <exception>
#include <string>
#include <iomanip>
# define MAX_BLOCK_DIM 1024

// Error Handling Wrapper
inline void checkCuda(cudaError_t result, const char* func, const char* file, int line) {
    if (result != cudaSuccess) {
        throw std::runtime_error(
            std::string("CUDA error at ") + file + ":" + std::to_string(line) +
            " (" + func + "): " + cudaGetErrorString(result)
        );
    }
}

#define CUDA_CALL(func) checkCuda((func), #func, __FILE__, __LINE__)

// Memory Handling Wrapper - RAII
template <typename T>
class CudaMemory {
public:
    explicit CudaMemory(size_t size) 
    {
        ptr = nullptr;
        CUDA_CALL(cudaMalloc((void**)&ptr, size));
    }

    // Prevent copying
    CudaMemory(const CudaMemory&) = delete;
    CudaMemory& operator=(const CudaMemory&) = delete;
    
    // Allow Moving
    CudaMemory(CudaMemory&& other) noexcept : ptr(other.ptr) { other.ptr = nullptr; }
    CudaMemory& operator=(CudaMemory&& other) noexcept {
        if (this != &other) {
            if (ptr) cudaFree(ptr);
            ptr = other.ptr;
            other.ptr = nullptr;
        }
        return *this;
    }

    ~CudaMemory() {  if (ptr) cudaFree(ptr); }

    T* get() const { return ptr; }

private:
    T* ptr;
};

    
    __global__ void addKernel(int* c, const int* a, const int* b, const unsigned long long length)
{
    unsigned long long idx = (blockIdx.x * blockDim.x) + threadIdx.x;
    
    if (idx < length)
    {
        c[idx] = a[idx] + b[idx];
    }
}

void printMemoryRequirements(unsigned long long array_len, unsigned long long chunk_len = 0)
{
    long double array_size_bytes = array_len * sizeof(float);
    long double array_size_gbytes = array_size_bytes / (1024 * 1024 * 1024);
    long double array_size_mbytes = array_size_bytes / (1024 * 1024);

    std::cout << "---Memory Requirements---" << std::endl;
    std::cout << "Array Length: " << array_len << std::endl;
    std::cout << "Host Array Memory Size: " << array_size_gbytes << "GB, " << array_size_mbytes <<"MB" << std::endl;

    if (chunk_len > 0)
    {
        long double chunk_size_bytes = chunk_len * sizeof(float);
        long double chunk_size_gbytes = chunk_size_bytes / (1024 * 1024 * 1024);
        long double chunk_size_mbytes = chunk_size_gbytes / (1024 * 1024);

        std::cout << "Chunk Length: " << chunk_len << std::endl;
        std::cout << "GPU  Chunk Per Array Memory: " << chunk_size_gbytes << " GB" << std::endl;
        std::cout << "GPU  Chunk Total Array Memory: " << chunk_size_gbytes * 3 << "GB, " << chunk_size_mbytes * 3 << "MB" << std::endl << std::endl;
    }
}

void printKernelConfig(dim3 grid, dim3 block)
{
    std::cout << "Grid: " << grid.x << " " << grid.y << " " << grid.z << std::endl;
    std::cout << "Block: " << block.x << " " << block.y << " " << block.z << std::endl;
}

void addWithCuda(int* c, const int* a, const int* b, unsigned long long array_len)
{
    int* dev_a = 0;
    int* dev_b = 0;
    int* dev_c = 0;
    
    int mem_size = array_len * sizeof(int);
    // Allocate GPU buffers for three vectors (two input, one output)    .
    CUDA_CALL(cudaMalloc((void**)&dev_c, mem_size));
    CUDA_CALL(cudaMalloc((void**)&dev_a, mem_size));
    CUDA_CALL(cudaMalloc((void**)&dev_b, mem_size));

    // Copy input vectors from host memory to GPU buffers.
    CUDA_CALL(cudaMemcpy(dev_a, a, mem_size, cudaMemcpyHostToDevice));
    CUDA_CALL(cudaMemcpy(dev_b, b, mem_size, cudaMemcpyHostToDevice));
 
    // Launch a kernel on the GPU with one thread for each element.
    int blockDim = MAX_BLOCK_DIM;
    int gridDim = (array_len + blockDim - 1) / blockDim;
    addKernel<<<gridDim, blockDim>>>(dev_c, dev_a, dev_b, array_len);

    // Check for any errors launching the kernel
    CUDA_CALL(cudaGetLastError());

    // cudaDeviceSynchronize waits for the kernel to finish
    CUDA_CALL(cudaDeviceSynchronize());

    // Copy output vector from GPU buffer to host memory.
    CUDA_CALL(cudaMemcpy(c, dev_c, mem_size, cudaMemcpyDeviceToHost));

Error:
    cudaFree(dev_c);
    cudaFree(dev_a);
    cudaFree(dev_b);
}

void addWithCudaMemSafe(int* c, const int* a, const int* b, unsigned long long array_len)
{
    // Allocate GPU buffers for three vectors (two input, one output)
    size_t mem_size = array_len * sizeof(int);
    CudaMemory<int> dev_a(mem_size), dev_b(mem_size), dev_c(mem_size);

    // Copy input vectors from host memory to GPU buffers.
    CUDA_CALL(cudaMemcpy(dev_a.get(), a, mem_size, cudaMemcpyHostToDevice));
    CUDA_CALL(cudaMemcpy(dev_b.get(), b, mem_size, cudaMemcpyHostToDevice));

    // Launch a kernel on the GPU with one thread for each element.
    dim3 blockDim(MAX_BLOCK_DIM);
    dim3 gridDim((array_len + blockDim.x - 1) / blockDim.x);
    //printKernelConfig(gridDim, blockDim);
    addKernel<<<gridDim, blockDim>>>(dev_c.get(), dev_a.get(), dev_b.get(), array_len);
    // Check for any errors launching the kernel
    CUDA_CALL(cudaGetLastError());
 
    // cudaDeviceSynchronize waits for the kernel to finish
    CUDA_CALL(cudaDeviceSynchronize());

    // Copy output vector from GPU buffer to host memory.
    CUDA_CALL(cudaMemcpy(c, dev_c.get(), mem_size, cudaMemcpyDeviceToHost));
}

void printDeviceDetails()
{
    cudaDeviceProp prop;
    int deviceId = 0; // Use 0 for the first GPU

    size_t free_mem, total_mem;



    CUDA_CALL(cudaGetDeviceProperties(&prop, deviceId));
    CUDA_CALL(cudaMemGetInfo(&free_mem, nullptr));

    // Convert to MB
    total_mem = prop.totalGlobalMem / (1024 * 1024);
    free_mem = free_mem / (1024 * 1024);

    printf("Device Name: %s\n", prop.name);
    printf("SM Count: %d\n", prop.multiProcessorCount);
    printf("Total Global Memory: %zu Mbytes\n", total_mem);
    printf("Current Free Memory: %zu Mbytes\n", free_mem);

    printf("\n---Block Limits---\n");
    printf("Max Threads per Block: %d\n", prop.maxThreadsPerBlock);
    printf("Max Block Dimension: %d %d %d\n", prop.maxThreadsDim[0], prop.maxThreadsDim[1], prop.maxThreadsDim[2]);
    printf("Max Grid Size: %d %d %d\n", prop.maxGridSize[0], prop.maxGridSize[1], prop.maxGridSize[2]);

    printf("\n---Memory Limits per Block---\n");
    printf("Registers per Block: %d\n", prop.regsPerBlock);
    printf("Shared Memory per Block: %d\n", prop.sharedMemPerBlock);
        
        
    printf("\n---Clock Rates---\n");
    printf("Clock Rate: %d KHz\n", prop.clockRate);
    printf("Memory Clock Rate: %d KHz\n", prop.memoryClockRate);
    printf("\n");
}

void pageableMemoryAddition(unsigned long long array_len)
{
    // Host Data
    int* h_A, * h_B, * h_C;
    size_t mem_size = array_len * sizeof(int);

    // Host Data pageable memory
    h_A = (int*)malloc(mem_size);
    h_B = (int*)malloc(mem_size);
    h_C = (int*)malloc(mem_size);

    // Initialize Host Data
    std::fill(h_A, h_A + array_len, 42);
    std::fill(h_B, h_B + array_len, 38);
    std::fill(h_C, h_C + array_len, 0);

    // Add Vector
    addWithCudaMemSafe(h_C, h_A, h_B, array_len);

    std::cout << "Result: " << h_C[0] << " " << h_C[array_len - 1] << std::endl;
   
    // free host memory
    free(h_A);
    free(h_B);
    free(h_C);
}

void pinnedMemoryAddition(unsigned long long array_len)
{
    // Host Data
    int* h_A, * h_B, * h_C;
    size_t mem_size = array_len * sizeof(int);

    // Host Data pinned memory
    CUDA_CALL(cudaMallocHost(&h_A, mem_size));
    CUDA_CALL(cudaMallocHost(&h_B, mem_size));
    CUDA_CALL(cudaMallocHost(&h_C, mem_size));

    // Initialize Host Data
    std::fill(h_A, h_A + array_len, 42);
    std::fill(h_B, h_B + array_len, 38);
    std::fill(h_C, h_C + array_len, 0);

    std::cout << "Initialized A:" << h_A[0] << "  B:" << h_B[0] << std::endl;

    // Add Vector
    addWithCudaMemSafe(h_C, h_A, h_B, array_len);

    // Print Result
    std::cout << "Result: " << h_C[0] << " " << h_C[array_len - 1] << std::endl;

    // free host memory
    cudaFreeHost(h_A);
    cudaFreeHost(h_B);
    cudaFreeHost(h_C);
}

void pageableMemoryAdditionLarge(unsigned long long array_len, float free_mem_threshold=0.2)
{
    std::srand(std::time(nullptr));

    // Chunk size based on FreeMemory Available
    size_t free_mem;
    CUDA_CALL(cudaMemGetInfo(&free_mem, nullptr));

    size_t total_max_mem = free_mem * free_mem_threshold; // Limit memory usage in GPU
    size_t vec_max_mem = total_max_mem / 3; // A,B,C Vectors
    size_t vec_max_len = vec_max_mem / sizeof(int);

    //std::cout << "Max Memory: " << total_max_mem << " Bytes" << std::endl;
    //std::cout << "Max Per Vector Memory: " << vec_max_mem << " Bytes" << std::endl;
    //std::cout << "Max Per Vector Length per chunk: " << vec_max_len << std::endl;

    // Compute chunk config
    unsigned long long chunk_len = vec_max_len - (vec_max_len % MAX_BLOCK_DIM); // Making sure chunks can be divided into max block dim
    size_t chunk_num = array_len / chunk_len;

    unsigned long long final_chunk_len = array_len - (chunk_num * chunk_len);
    assert(((chunk_num * chunk_len) + final_chunk_len) == array_len); // Assert we don't miss any elts from the array
    assert(chunk_len >= MAX_BLOCK_DIM); // Chunk should fill the block size

    //std::cout << "Full Array Length: " << array_len << std::endl;
    std::cout << "Number of Chunks: " << chunk_num << std::endl;
    //std::cout << "Chunk length: " << chunk_len << std::endl;
    //std::cout << "Final Chunk length: " << final_chunk_len << std::endl;

    //printMemoryRequirements(array_len, chunk_len);

    // Host Data
    int* h_A, * h_B, * h_C;
    size_t mem_size = array_len * sizeof(int);

    // Host Data pageable memory
    h_A = (int*)malloc(mem_size);
    h_B = (int*)malloc(mem_size);
    h_C = (int*)malloc(mem_size);

    // Initialize Host Data
    /*for (unsigned long long i = 0; i < array_len; ++i)
    {
        h_A[i] = 1 + std::rand() % 100;
        h_B[i] = 1 + std::rand() % 100;
    }*/
    std::fill(h_A, h_A + array_len, 42);  // Fill with 42
    std::fill(h_B, h_B + array_len, 100); // Fill with 100
    std::fill(h_C, h_C + array_len, 0); // Fill with 255

    std::cout << "Host Initialized -> Launching Kernels" << std::endl;

    //Add Vector in Chunks
    // Allocate GPU buffers for three vectors (two input, one output)
    size_t chunk_mem_size = chunk_len * sizeof(int);
    CudaMemory<int> dev_a(chunk_mem_size), dev_b(chunk_mem_size), dev_c(chunk_mem_size);

    unsigned long long chunk_offset = 0;
    for (int chunk_index = 0; chunk_index < chunk_num; chunk_index++)
    {
        chunk_offset = (chunk_index * chunk_len);
        //addWithCudaMemSafe(h_C + chunk_offset, h_A + chunk_offset, h_B + chunk_offset, chunk_len);

        // No memory realloc
        CUDA_CALL(cudaMemcpy(dev_a.get(), h_A + chunk_offset, chunk_mem_size, cudaMemcpyHostToDevice));
        CUDA_CALL(cudaMemcpy(dev_b.get(), h_B + chunk_offset, chunk_mem_size, cudaMemcpyHostToDevice));
        dim3 blockDim(MAX_BLOCK_DIM);
        dim3 gridDim((chunk_len + blockDim.x - 1) / blockDim.x);
        addKernel <<<gridDim, blockDim >>> (dev_c.get(), dev_a.get(), dev_b.get(), chunk_len);
        CUDA_CALL(cudaGetLastError());
        CUDA_CALL(cudaDeviceSynchronize());
        CUDA_CALL(cudaMemcpy(h_C + chunk_offset, dev_c.get(), chunk_mem_size, cudaMemcpyDeviceToHost));
    }

    // Process final chunk if there are any leftover elements
   /* if (final_chunk_len > 0)
    {
        chunk_offset = chunk_num * chunk_len;
        addWithCudaMemSafe(h_C + chunk_offset, h_A + chunk_offset, h_B + chunk_offset, final_chunk_len);
    }*/

    // free host memory
    free(h_A);
    free(h_B);
    free(h_C);
}

void streamedVectorAdditionLarge(unsigned long long array_len, float free_mem_threshold = 0.2)
{
    const int num_streams = 4;
    assert(free_mem_threshold <= 1);

    // Host Data
    int* h_A, * h_B, * h_C;
    size_t mem_size = array_len * sizeof(int);

    // Device Data pinned memory for streams
    cudaMallocHost(&h_A, mem_size);
    cudaMallocHost(&h_B, mem_size);
    cudaMallocHost(&h_C, mem_size);

    // Initialize Host Data
    std::fill(h_A, h_A + array_len, 42);
    std::fill(h_B, h_B + array_len, 100);
    std::fill(h_C, h_C + array_len, 0);

    // Chunk size based on FreeMemory Available
    size_t free_mem;
    CUDA_CALL(cudaMemGetInfo(&free_mem, nullptr));
    size_t total_max_mem = free_mem * free_mem_threshold; // Limit memory usage in GPU
    int num_vecs_in_device = 3 * num_streams; // A,B,C for each N Streams
    size_t vec_max_mem = total_max_mem / num_vecs_in_device;
    size_t vec_max_len = vec_max_mem / sizeof(int);

    // Compute chunk config
    unsigned long long chunk_len = vec_max_len - (vec_max_len % MAX_BLOCK_DIM); // Making sure chunks can be divided into max block dim
    size_t chunk_num = array_len / chunk_len; // Total number of chunks to be processed
    int chunk_mem_size = chunk_len * sizeof(int);

    std::cout << "Number of Chunks: " << chunk_num << std::endl;

    //Create Streams
    cudaStream_t streams[num_streams];
    for (int i = 0; i < num_streams; i++) 
    {
        cudaStreamCreate(&streams[i]);
    }
    
    std::cout << "Host Initialized -> Launching Kernels" << std::endl;

    // Device Storage Data for each stream
    std::vector<CudaMemory<int>> dev_a, dev_b, dev_c;
    for (int i = 0; i < num_streams; ++i) 
    {
        dev_a.emplace_back(chunk_mem_size);
        dev_b.emplace_back(chunk_mem_size);
        dev_c.emplace_back(chunk_mem_size);
    }

    dim3 blockDim(MAX_BLOCK_DIM);
    dim3 gridDim((chunk_len + blockDim.x - 1) / blockDim.x);

    // Process Vector in Stream Chunks
    for (int chunk_index = 0; chunk_index < chunk_num; chunk_index = chunk_index + num_streams)
    {
        for (int stream_index = 0; stream_index < num_streams; stream_index++)
        {
            int chunk_offset = (chunk_index+stream_index) * chunk_len;
            //std::cout << "Chunk:" << chunk_index << "  Offset:" << chunk_offset << std::endl;
            
            // Transfer Data to GPU Stream 1
            CUDA_CALL(cudaMemcpyAsync(dev_a[stream_index].get(), h_A + chunk_offset, chunk_mem_size, cudaMemcpyHostToDevice, streams[stream_index]));
            CUDA_CALL(cudaMemcpyAsync(dev_b[stream_index].get(), h_B + chunk_offset, chunk_mem_size, cudaMemcpyHostToDevice, streams[stream_index]));
            
            // Kernel
            addKernel<<<gridDim, blockDim, 0, streams[stream_index]>>>(dev_c[stream_index].get(), dev_a[stream_index].get(), dev_b[stream_index].get(), chunk_len);
            // Check for any errors launching the kernel
            CUDA_CALL(cudaGetLastError());

            // Transfer back to Host
            CUDA_CALL(cudaMemcpyAsync(h_C + chunk_offset, dev_c[stream_index].get(), chunk_mem_size, cudaMemcpyDeviceToHost, streams[stream_index]));
        }
    }

    // Wait until streams are done
    for (int i = 0; i < num_streams; i++)
    {
        cudaStreamSynchronize(streams[i]);
    }

    // Destroy Streams
    for (int i = 0; i < num_streams; i++)
    {
        cudaStreamDestroy(streams[i]);
    }
    
    // free host memory
    cudaFreeHost(h_A);
    cudaFreeHost(h_B);
    cudaFreeHost(h_C);
}

int main()
{
    // Choose GPU
    CUDA_CALL(cudaSetDevice(0));

    printDeviceDetails();

    try
    {
        enum Options { PageableMemoryVectorAddition, PinnedMemoryVectorAddition, PageableMemoryVectorAdditionLarge, StreamedVectorAdditionLarge };

        Options option = PageableMemoryVectorAdditionLarge;
        unsigned long long array_len, chunk_len;
        
        switch (option)
        {
        case PageableMemoryVectorAddition:
            array_len = 1024 * 1024 * 256;
            printMemoryRequirements(array_len);
            pageableMemoryAddition(array_len);
            break;
        
        case PinnedMemoryVectorAddition:
            array_len = 1024 * 1024 * 256;
            chunk_len = MAX_BLOCK_DIM;
            printMemoryRequirements(array_len);
            pinnedMemoryAddition(array_len);
            break;

        case PageableMemoryVectorAdditionLarge: // chunked execution for very large array
            array_len = 1ULL * 1024 * 1024 * 512;
            //printMemoryRequirements(array_len);
            pageableMemoryAdditionLarge(array_len);
            break;
        
        case StreamedVectorAdditionLarge: // streamed chunk execution for very large array
            array_len = 1ULL * 1024 * 1024 * 512;
            streamedVectorAdditionLarge(array_len);
        
        default:
            break;
        }
        
        //pageableMemoryAddition(arraySize, chunkSize);
        //pinnedMemoryAddition(arraySize, chunkSize);
        //streamedAddition(arraySize);

        // cudaDeviceReset - for profiling
        CUDA_CALL(cudaDeviceReset());
    } catch (std::exception& e) {
        fprintf(stderr, "Exception: %s\n", e.what()); 
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}

 