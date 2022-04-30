# this file uses pyinstaller to create the binary tarball that is used to deploy the tool binary
# this allows the tool binary to be deployed without installing python and other required python packages
#
TOOL=`basename $PWD`
MAIN=$TOOL.py
TARGET=tarball/$TOOL

pyinstaller --add-data scripts.d:scripts.d --onefile $MAIN
#pyinstaller --onefile $MAIN

#mkdir -p $TARGET
#cp dist/$TOOL $TARGET
#cp -r scripts.d $TARGET
#cp README.md $TARGET
#
#cd tarball
#tar cvzf ../${TOOL}.tar $TOOL




#BIN=wekachecker
#TARGET=tarball
#
#pyinstaller --clean --onefile $BIN.py
#
#mkdir -p $TARGET
#cp dist/$BIN $TARGET
#cp -r scripts.d $TARGET
#cp README.md $TARGET
#cd $TARGET
#tar cvzf ../$BIN.tar $BIN
