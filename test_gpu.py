import torch
import time
import multiprocessing as mp

def stress_test_gpu(gpu_id, duration=600):
    """
    在指定的 GPU 上运行高强度矩阵乘法进行压力测试
    :param gpu_id: GPU 的编号 (例如 0, 1, 2...)
    :param duration: 测试持续时间，单位为秒 (600秒 = 10分钟)
    """
    try:
        # 指定当前进程使用的显卡
        device = torch.device(f"cuda:{gpu_id}")
        
        # 定义两个超大矩阵 (8192x8192 大概占用几百MB显存，但足以让算力满载)
        # 如果你想把显存也塞满，可以适当调大这个数值，比如 16384
        matrix_size = 8192 
        
        print(f"[GPU {gpu_id}] 压力测试已启动，将持续 {duration / 60} 分钟...")
        
        # 将张量加载到对应的 GPU 上
        a = torch.randn(matrix_size, matrix_size, device=device)
        b = torch.randn(matrix_size, matrix_size, device=device)
        
        start_time = time.time()
        end_time = start_time + duration
        
        # 持续循环进行矩阵乘法，直到时间结束
        while time.time() < end_time:
            c = torch.matmul(a, b)
            # 强制同步，确保 GPU 真的在计算，而不是把任务堆积在 CPU 的下发队列里
            torch.cuda.synchronize(device)
            
        print(f"[GPU {gpu_id}] 测试完成！")
        
    except Exception as e:
        print(f"[GPU {gpu_id}] 测试发生错误: {e}")

if __name__ == '__main__':
    # PyTorch 在多进程调用 CUDA 时，必须使用 'spawn' 模式启动进程
    mp.set_start_method('spawn', force=True)
    
    # 获取当前服务器上的可用 GPU 总数
    num_gpus = torch.cuda.device_count()
    
    if num_gpus == 0:
        print("未检测到可用的 GPU，请检查 NVIDIA 驱动或 PyTorch 的 CUDA 支持！")
        exit()
        
    print(f"检测到 {num_gpus} 张 GPU，准备开始 10 分钟压力测试...")
    
    processes = []
    
    # 为每一张显卡启动一个独立的测试进程
    for i in range(num_gpus):
        p = mp.Process(target=stress_test_gpu, args=(i, 600)) # 600秒 = 10分钟
        p.start()
        processes.append(p)
        
    # 等待所有进程执行完毕
    for p in processes:
        p.join()
        
    print("所有 GPU 的 10 分钟压力测试已全部结束！")
