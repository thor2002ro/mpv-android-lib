#pragma once

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>
#ifdef __ANDROID__
#include <pthread.h>
#endif

// One queue preserves command/write/read order without waiting on the caller.
class PlaybackWorker {
    std::mutex mutex;
    std::condition_variable ready;
    std::deque<std::function<void()>> tasks;
    bool stopping = false;
    std::thread thread;

public:
    PlaybackWorker() : thread([this] {
#ifdef __ANDROID__
        pthread_setname_np(pthread_self(), "mpv-playback");
#endif
        for (;;) {
            std::function<void()> task;
            {
                std::unique_lock<std::mutex> lock(mutex);
                ready.wait(lock, [this] { return stopping || !tasks.empty(); });
                if (tasks.empty()) return;
                task = std::move(tasks.front());
                tasks.pop_front();
            }
            task();
        }
    }) {}

    ~PlaybackWorker() { stop(); }

    bool post(std::function<void()> task) {
        std::lock_guard<std::mutex> lock(mutex);
        if (stopping) return false;
        tasks.push_back(std::move(task));
        ready.notify_one();
        return true;
    }

    // Only callers needing an actual result wait; reentrant reads cannot deadlock.
    int run(std::function<int()> task) {
        if (std::this_thread::get_id() == thread.get_id()) return task();
        std::mutex doneMutex;
        std::condition_variable done;
        bool finished = false;
        int result = -1;
        if (!post([&] {
            int value = task();
            std::lock_guard<std::mutex> lock(doneMutex);
            result = value;
            finished = true;
            done.notify_one();
        })) return -1;
        std::unique_lock<std::mutex> lock(doneMutex);
        done.wait(lock, [&] { return finished; });
        return result;
    }

    void stop() {
        {
            std::lock_guard<std::mutex> lock(mutex);
            stopping = true;
            ready.notify_one();
        }
        if (thread.joinable()) thread.join();
    }
};
