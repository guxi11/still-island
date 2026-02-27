# Guideline 2.5.4 - Performance - Software Requirements

The app declares support for Voice-over IP (VoIP) in the UIBackgroundModes key in your Info.plist, but we are unable to locate any VoIP services. Apps that declare support for VoIP in the UIBackgroundModes key in your Info.plist file must have features that require VoIP.

Next Steps

If the app has a feature that requires VoIP, reply to this message and let us know how to locate this feature. If the app does not have a feature that requires VoIP, it would be appropriate to remove the "voip" value from the UIBackgroundModes key.

Note that using VoIP only for its "keep alive" functionality is not the intended purpose of VoIP. 

# Guideline 5.1.2 - Legal - Privacy - Data Use and Sharing

The app accesses user data from the device but does not have the required precautions in place.

Specifically, the app uploads the user's Contact to a server, but the app does not inform the user and request their consent first.

Next Steps

To collect personal data with the app:

- The app must make it clear to the user that their personal data will be uploaded to a server and you must obtain the user's consent before the data is uploaded. 

- The app must state what you will do with the user's Contacts once they have been uploaded to a server. If the app is not does not upload the user's Contacts to a server, reply to this message and let us know.


Resources

There are keys for specifying the reason the app will access the user's protected data. When the access prompt is displayed, the purpose specified in these keys is displayed in that dialog box. If the app will be transmitting protected user data, the usage string in your access request should clearly inform the user that their data will be uploaded to your server if they consent.

For more information on these keys, please review the Information Property List Key Reference.


# Guideline 1.5 - Safety
Issue Description



The Support URL provided in App Store Connect, https://github.com/guxi11/porthole/issues, is currently not functional and/or displays an error. 

Next Steps

Update the specified Support URL to direct users to a functional webpage with support information.

Resources

Learn about Support URLs and other platform version information on App Store Connect Help.
