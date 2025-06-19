# 📍 Tracking App – Frontend
This is the frontend of our Tracking App, designed to visualize GPS data, altitude profiles, and route statistics. 

## Installation Guide
This is a guide to run the app on real Android device on Ubuntu from scratch.

The steps were made on a following system:\
Operating system: Ubuntu 24.04.2 LTS x86_64\
Desktop environment: GNOME 46.0\
Window manager: Mutter\
<img src="https://github.com/user-attachments/assets/221fa001-af55-4355-9e96-54b3542a364a" alt="PC info" width="450"/>

**Flutter**:\
To run the application first step is to install Flutter framework. Package requirements for Flutter are\
`curl git unzip xz-utils zip libglu1-mesa`

Now download Flutter SDK tar.xz from this link [Flutter SDK](https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.3-stable.tar.xz). And extract the file into any directory you feel comfortable with, but keep in mind that we will use the directory path later. To extract the file you can use following command (It assumes you have the tar.xz file in **~/Downloads** directory\
`tar -xf ~/Downloads/flutter_linux_3.29.3-stable.tar.xz -C ~/a/path/to/directory/`

Add the Flutter SDK to PATH, so you can use it in any directory in terminal. Please, use the directory to Flutter SDK (directory path from previous section). If you use bash shell you can use following command\
`echo 'export PATH="$HOME/a/path/to/directory/flutter/bin:$PATH"' >> ~/.bash_profile`

To check if Flutter was properly install you can use\
`flutter doctor`

Since we plan to run the app on Android (iPhone simulator can not be run on non MacOs machines), we will be needing Android Studio. However, the IDE choice for this guide is VisualStudio Code (more on that later). Package requirements for Android Studio are\
`libc6:amd64 libstdc++6:amd64 lib32z1 libbz2-1.0:amd64`\
The link to Android Studio is [Android Studio](https://developer.android.com/studio/install#linux)

Android device setup:
1. **Very important** Ensure that you have VM acceleration enabled in BIOS. Enabling process this option is different for every PC.
2. Open Android Studio
3. Click on burger menu on top left
4. Select Tools tab
5. Select Device Managet option and separate section should appear on the right\
  <img src="https://github.com/user-attachments/assets/de575d40-f141-4a80-9f0e-b89be1665851" alt="Device manager section" width="450"/>

7. Select the icon similar to wifi. This will allow you to connect real device per Wi-Fi
8. A QR code will appear. So scan it on real device to connect it
  <img src="https://github.com/user-attachments/assets/ca4c1342-c3a2-4b48-b679-6f9f4e531b44" alt="QR code window" width="450"/>

**IDE**:\
For a reason that Visual Studio Code is broadly used this guide considers VS Code as IDE.\
Here is the link to install it https://code.visualstudio.com/download\
Confusing part in installing the Flutter extension for VS Code is it will need to locate the Flutter SDK.\


In the end check if everything works alright with help of "flutter doctor" in the project directory. This will print the information about your system and issues in certain categories

## Issue that might arise:
Android license - you will need to agree to android license before running the app, the command for it is\
`flutter doctor --android-licenses`

Android SDK Command-line Tools are necessary for proper work of project. Install steps are:
1. Go to "Tools" tab in Android Studio
2. Click on SDK Manager and new window is opened
3. In "Android SDK" tab a "SDK Platforms" should be already selected. Click on SDK Tools.
4. Checkmark "Android SDK Command-line Tools" to install

## Code Coverage

You can view the full coverage report [here](https://caiproj.github.io/frontend/).

