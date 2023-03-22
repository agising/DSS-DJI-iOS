# DSS-DJI-iOS
The RISE DSS for DJI on iOS

# Installation
Frameworks are installed using cocoapods.
Mid 2021 there are some issues related to the Apple M1 chip. This worked for me:
    
    sude gem uninstall cocoapods
    brew install cocoapods
    pod setup
From the DSS-folder, install the pods
    
    pod install

Somewhere in the process pod install complained about xcode command line tools, I then relinked to the application it self with the command below. It is possible that brew does that automagically.
    
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer


# Create a secrets file and put bundle id and developer team there.
In XCODE, at the top level in the file tree, right click DSS and add file, choose config file. Add the following keys in the end:
PRODUCT_BUNDLE_IDENTIFIER = com.your_bundle.id
DEVELOPMENT_TEAM = dev_team_as_a_code

Make the project read from this secret file:
Now select DSS, highlight DSS under Project.
Under configurations, expand debug, select DSS project (first level).
Add Secret_config
Under configurations, expand release, select DSS project (first level).
Add Secret_config

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
 
