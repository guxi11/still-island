
我是一个ios的开发者，我开发了一个可以利用pip画中画技术来实时显示后置摄像头画面的app，来让用户拥有类似在屏幕上打开了一扇窗户的体验。用户在进入首页之后，就能屏幕中央看到一个名为“实景”的卡片（在截图里有），为了在后台实时获取相机数据，在ai的帮助下似乎只能申请使用voip权限。
请深度思考，确认如果要实现“实景”的需求，是否必须要申请viop权限，以及申请之后，如何通过apple 的审核。如下是我们的对话列表：

[apple]

Guideline 2.5.4 - Performance - Software Requirements

The app declares support for Voice-over IP (VoIP) in the UIBackgroundModes key in your Info.plist, but we are unable to locate any VoIP services. Apps that declare support for VoIP in the UIBackgroundModes key in your Info.plist file must have features that require VoIP.

Next Steps

If the app has a feature that requires VoIP, reply to this message and let us know how to locate this feature. If the app does not have a feature that requires VoIP, it would be appropriate to remove the "voip" value from the UIBackgroundModes key.

Note that using VoIP only for its "keep alive" functionality is not the intended purpose of VoIP. 

Resources 

- Learn more about software requirements in guideline 2.5.4.
- Review documentation for the UIBackgroundModes key.

[me]

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

[apple]

The app declares support for Voice-over IP (VoIP) in the UIBackgroundModes key in your Info.plist, but we are still unable to locate any VoIP services. Specifically, the Picture-in-Picture (PIP) feature is not part of the VoIP services.

Apps that declare support for VoIP in the UIBackgroundModes key in your Info.plist file must have features that require VoIP.

Next Steps

If the app has a feature that requires VoIP, reply to this message and let us know how to locate this feature. If the app does not have a feature that requires VoIP, it would be appropriate to remove the "voip" value from the UIBackgroundModes key.

Note that using VoIP only for its "keep alive" functionality is not the intended purpose of VoIP. 
