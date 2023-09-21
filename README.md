# DSS-DJI-iOS
This is the DJI iOS implementation of the DSS. It comes as is, we wish it was in a more general state, but currently it is working fine for our purposes.
Using this app, you can write an other application that sends commands to this app that will routes them further to the DJI drone. Refer to the main repo https://github.com/RISE-drones/rise_drones

# Legal
If uploading any code to apple servers, the DJI-SDK is in one way or the other included. When downloading your code from apple servers the code is technically exported from USA and there might be export restrictions due to encryption technologies included. We cannot give any legal advise in this matter, it is on your own responsibility to resarch the legal aspects of dealing and handligth this software.


# Future work
There is a default viewcontroller from DJI that pretty much gives the base functionality of the standard app, with menus ans such. It was once implemented, but removed because downloading photos took for ever since the camera could not be stopped during the process. However, new versions of the DJI SDK does not allow to to stop the camera as before and we are back to slow download speeds..

Also, implementing the same functionality for Android is higly wanted to be able to run the software on DJI handcontrollers with integrated screens.

# Installation
This installation description is not complete. Please contribute whith how you install it. Also, updates in XCODE will outdate instructions.

## Frameworks are installed using cocoapods.
The proejct utilizes cocoapds to install dependencies, first install cocoapods:
    brew install cocoapods
    pod setup
Quit Xcode, then install the pods. Browse to the DSS-folder and install the pods that are defined in the Podfile:
    cd DSS-DJI-IOS/DSS/
    pod install

You might get warnings aboout xcode command line tools. you can try to relink xcode to it self using the following command.

    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

From here on it is important that ou start Xcode using the newly created DSS.xcworkspace. Do not use the .xcodeproj


## Secret information
You need some private keys (secrets) in order to compile the code and make it conenct to a drone. These secrets must be outside the git-control for safety reasons. Therefor we do not add this kind of info directly inte the info.plist file, instead we reference to two secret files as described in the following sections.

## Create a Secret_config file and put apple bundle id and developer team there.
In XCODE, at the top level in the file tree, right click DSS and select new file, choose Configurations Settings file and name it Secrets_config (xcode will add the correct file ending).
Add the following keys in the end:

    PRODUCT_BUNDLE_IDENTIFIER = com.your_bundle.id
    DEVELOPMENT_TEAM = dev_team_as_a_code

Now, make the project read from this secret file by following these steps

- Select DSS in Project navigator (top left), in project and targets list, highlight DSS under Project. Tab Info
    - Under Title Configurations:
      - Expand debug, select DSS project (first level).
      - Select Secret_config
      - Expand release
      - Select DSS project (first level).
      - Add Secret_config

## Create Secrets.h and put your DJI bundle id here 
In Xcode, in the file tree (project navigator), goto DSS/DSS. The reference Secrets is marked red because the Secret file is missing. Copy the Secrets-Sample file to Secrets. Add you DJI key here. The creation of this file was supposed to happen automatically in the build phase, but it does not seem to work. (You can also remove the red reference and rename the Secrets-Sample to Secrets (.h).)
Add you DJI app key in the file Secrets.h.

\#define SECRET_DJISDKKEY    c0asdfasdfasdfasdfasdfqwert


## Compile
Try to compile to a phone connected via cable. If there are complaints about secret info like bundle id and such, follow the below steps.

- Select DSS in Project navigator (top left), in project and targets list, highlight DSS under Project.
  - Select tab build settings, highlight All and Levels.
  - Search for bundle_id.
  - Under Packaging, select Product Bundle Identifier and press Delete. Xcode will read from the config file and under resolved it will show what you entered in the secrets file.

  - Search for development_team
  - Under signing, select Development team and press Delete. Xcode will read from the config file and under resolved it will show what tou entered in the secrets file.

- Select DSS in Project navigator (top left), in project and targets list, highlight DSS under Target.
  - Select tab build settings, hightlihgt All and Levels, serach for bundle_id.
  - Under Packaging, select Product Bundle Identifier. Xcode will read from the config file and under resolved it will show the apple bundle id tou entered in the Secret_config filewhat you entered in the secrets file.
  - Search for development_team
  - Under signing, select Development team and press Delete. Xcode will read from the config file and under resolved it will show what tou entered in the secrets file.


# Contributing
If you would want to contribute to RISE drone system please take a look at [the guide for contributing](contributing.md) to find out more about the guidelines on how to proceed.

# License
RISE drone system is realeased under the [BSD 3-Clause License](https://opensource.org/licenses/BSD-3-Clause)
