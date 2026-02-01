# ask
需求：提升app在使用pip时的性能，降低耗电量。
背景：现在app在播放视频或者展示摄像头实景的时候性能很差。原因是为了在后台展示，使用video之前一直会失败，所以使用了 sprits相同的方案，导致性能更差。
参考：
- 视频优化：参考视频通话/视频 App (YouTube/Netflix)，充分利用视频硬件解码器的能力。
- 渲染机制优化:
  - 避免使用 UIView.drawHierarchy 或 snapshotView 这种高层级 API，非常慢且耗费 CPU。 
  - 改用 Core Animation 层级甚至 Metal（如果有能力）直接生成 CVPixelBuffer，跳过 UIKit 的繁重布局计算。

> /cost 
  ⎿ Total duration (API):  10m 13.2s
    Total duration (wall): 11m 27.5s
    Total code changes:    520 lines added, 263 lines removed
    Usage by model:
          claude-4.5:      1.3M input, 19.7k output, 1.2M cache read, 0 cache write

124.34/25000
