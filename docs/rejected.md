
我是一个ios的开发者，我开发了一个可以利用pip画中画技术来实时显示后置摄像头画面的app，来让用户拥有类似在屏幕上打开了一扇窗户的体验。用户在进入首页之后，就能屏幕中央看到一个名为“实景”的卡片（在截图里有），为了在后台实时获取相机数据，在ai的帮助下似乎只能申请使用voip权限。

现在app在审核的时候被拒绝了，看起来是因为审核员不找不到在什么地方使用到了voip:
```
Guideline 2.5.4 - Performance - Software Requirements

The app declares support for Voice-over IP (VoIP) in the UIBackgroundModes key in your Info.plist, but we are unable to locate any VoIP services. Apps that declare support for VoIP in the UIBackgroundModes key in your Info.plist file must have features that require VoIP.

Next Steps

If the app has a feature that requires VoIP, reply to this message and let us know how to locate this feature. If the app does not have a feature that requires VoIP, it would be appropriate to remove the "voip" value from the UIBackgroundModes key.

Note that using VoIP only for its "keep alive" functionality is not the intended purpose of VoIP. 

Resources 

- Learn more about software requirements in guideline 2.5.4.
- Review documentation for the UIBackgroundModes key.
```

请用英文回复他，要有礼貌并且通俗易懂。同时还要提及我补充了一个视频预览和一张截图。直接输出回复内容，不要思考过程。

Dear App Review Team,

Thank you for your review and feedback regarding Guideline 2.5.4.

We are writing to clarify why our app, Porthole, requires the Voice-over IP (VoIP)
background mode. This permission is technically essential to power our "Real World"
feature, which is a core part of the app's functionality, rather than being used
simply to keep the app alive in the background.

The "Real World" feature allows users to open a floating Picture-in-Picture (PiP)
window that streams a live video feed from the device's rear camera. This effectively  creates a "window" on the screen, allowing users to see their physical surroundings
while using other apps. To maintain this active camera session and continuously
stream video frames to the PiP window while the app is in the background, the VoIP
background mode is required. Without it, the camera session is suspended by the
system, and the feature stops working immediately upon exiting the app.

To help you locate and verify this feature, we have uploaded a
screenshot demonstrating the "Real World" card and the live camera PiP functionality.
We hope this explanation clarifies the necessity of this permission for our specific
use case. Thank you for your time and assistance.

Best regards,

The Porthole Team

我现在提供的视频已经删除音频了，并且用ffmpeg处理了分辨率。
ffmpeg -i demo2.mp4 -acodec copy -crf 12 -vf scale=886:1920,setsar=1:1 preview1.mp4
上传会失败并提示：
你的app预览包含不受支持或已损坏的音频
请教我如何使用ffmpeg解决问题，请直接提供命令。如果是更复杂的问题，间断告诉我解决方案。

ffmpeg -i demo2.mp4 -c:v libx264 -crf 12 -vf "scale=886:1920,setsar=1:1" -an preview2.mp4

ffmpeg -i demo2.mp4 -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000" \
-c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -r 30 \
-vf "scale=886:1920,setsar=1:1" \
-c:a aac -b:a 128k -shortest \
preview_fixed.mp4

