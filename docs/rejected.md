
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



Dear Review Team,

Thank you for your continued review and feedback.

Regarding Guideline 2.5.4 (VoIP):

We understand the difficulty in testing this feature with a single device. The Voice
over IP functionality is used for real-time voice communication within our Focus Room
feature, which requires two physical devices on the same local Wi-Fi network.

We have attached a demo video demonstrating the full flow: creating a room on one
device, joining from a second device, and using the push-to-talk voice communication
between them. We hope this clearly demonstrates the VoIP functionality in our app.

To reproduce the feature:
1. Open the app on Device A → Tap the "Focus Room" card → Create a room
2. Open the app on Device B (same Wi-Fi) → Tap the "Focus Room" card → The room will
appear under "Nearby Rooms" → Tap to join
3. Once both devices are connected, long-press the microphone button on either device
to talk

Regarding Guideline 1.5 (Support URL):

We have updated our Support URL to our repository homepage, which now includes
contact information (email) and a link to the issues page for user support. Please
check the updated URL in App Store Connect.

Regarding Guideline 1.2 (User Generated Content - Anonymous Chat):

We would like to respectfully clarify that our Focus Room feature is not an anonymous
chat service. It is a local network productivity tool built on Apple's
MultipeerConnectivity framework, similar in nature to AirDrop or SharePlay. Here is
why we believe it does not fall under the anonymous chat category:

- Physical proximity required: Users must be connected to the same local Wi-Fi
network. They cannot discover or communicate with anyone outside their physical
network. This means users inherently know each other in person — they are coworkers
in the same office, classmates in the same room, or family members at home.
- No anonymous matching: There is no mechanism to match users with strangers. A user
must intentionally create a room, and only people on the same local network can see
and join it.
- Not a chat application: The voice feature is push-to-talk only (hold the microphone
button to speak), designed for brief coordination during focus sessions — not for
ongoing conversation or social interaction.
- Productivity purpose: The sole purpose of Focus Room is to help people in the same
physical space hold each other accountable during focused work sessions, similar to a
library study group.

Given these characteristics, we believe this feature is comparable to other local
network communication tools on iOS (such as AirDrop, Walkie-Talkie on Apple Watch, or
SharePlay) rather than an anonymous chat service.

Please let us know if you need any further clarification or additional materials.

Best regards



# Porthole

Porthole is an iOS app that helps you stay mindful of screen time by displaying
ambient information in Picture-in-Picture floating windows.

## Features

- **Clock Display** — Keep track of time with a floating clock
- **Pomodoro Timer** — Stay focused with a built-in timer
- **Focus Room** — Create or join a local network room to focus together with friends  - **Cat Companion** — A cute cat animation to keep you company
- **Camera Feed** — See the real world through a floating window
- **Usage Insights** — Track your screen time habits

## Support

If you encounter any issues or have feature requests, please:

- Open an issue on our [Issues page](https://github.com/guxi11/porthole/issues)
- Or contact us directly via email: **your-email@example.com**

## Privacy

Porthole respects your privacy. All data is stored locally on your device. Camera
feeds, voice communication, and focus room data are never uploaded to any server.
Voice communication in Focus Room uses local network only (peer-to-peer via
MultipeerConnectivity).
