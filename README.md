# DSS-DJI-iOS
This is the DJI iOS implementation of the DSS. It comes as is, we wish it was in a more general state, but currently it is working fine for our purposes.
Using this app, you can write an other application that sends commands to this app that will routes them further to the DJI drone. Refer to the main repo https://github.com/RISE-drones/rise_drones

# Legal
If uploadng any code to apple servers, the DJI-SDK is in one way or the other included. When downloading your code from apple servers the code is technically exported from USA and there might be export restrictions due to encryption technologies included. We cannot give any legal advise in this matter, it is on your own responsibility to resarch the legal aspects of dealing and handligth this software.


# Future work
There is a default viewcontroller from DJI that pretty much gives the base functionality of the standard app, with menus ans such. It was once implemented, but removed because downloading photos took for ever since the camera could not be stopped during the process. However, new versions of the DJI SDK does not allow to to stop the camera as before and we are back to slow download speeds..

Also, implementing the same functionality for Android is higly wanted to be able to run the software on DJI handcontrollers with integrated screens.

# Installation
This installation description is not complete. Please contribute whith how you install it. Also, updates in XCODE will outdate instructions.

## Frameworks are installed using cocoapods.
Mid 2021 there are some issues related to the Apple M1 chip. This worked for me:

    sudo gem uninstall cocoapods
    brew install cocoapods
    pod setup
From the DSS-folder, install the pods
    pod install

Somewhere in the process pod install complained about xcode command line tools, I then relinked to the application it self with the command below. It is possible that brew does that automagically.

    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

## Create a secrets file and put bundle id and developer team there.
In XCODE, at the top level in the file tree, right click DSS and add file, choose Configurations Settings file. Add the following keys in the end:
PRODUCT_BUNDLE_IDENTIFIER = com.your_bundle.id
DEVELOPMENT_TEAM = dev_team_as_a_code

Now, make the project read from this secret file:

Now select DSS, highlight DSS under Project.
Under configurations, expand debug, select DSS project (first level).
Add Secret_config
Under configurations, expand release, select DSS project (first level).
Add Secret_config

To clear out any already save secret info, make xcode get the info from the config file.

Update already stored values of secret info:
Now select DSS, highlight DSS under Project.
Select tab build settings, highlight All and Levels.
Search for bundle_id.
Under Packaging, select Product Bundle Identifier and press Delete. Xcode will read from the config file and under resolved it will show what you entered in the secrets file.
Search for development_team
Under signing, select Development team and press Delete. Xcode will read from the config file and under resolved it will show what tou entered in the secrets file.

Highlight DSS under Target.
Select tab build settings, hightlihgt All and Levels, serach for bundle_id.
Under Packaging, select Product Bundle Identifier. Xcode will read from the config file and under resolved it will show what you entered in the secrets file.
Search for development_team
Under signing, select Development team and press Delete. Xcode will read from the config file and under resolved it will show what tou entered in the secrets file.

## Create secret file for DJI key
Copy the Secrets-Sample file to Secrets. Add you DJI key here. The creation of this file was supposed to happen automatically in the build phase..

# Contributing
If you would want to contribute to RISE drone system please take a look at [the guide for contributing](contributing.md) to find out more about the guidelines on how to proceed.

# License
RISE drone system is realeased under the [BSD 3-Clause License](https://opensource.org/licenses/BSD-3-Clause)
