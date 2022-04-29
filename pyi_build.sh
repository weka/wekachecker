BIN=wekachecker
TARGET=tarball
pyinstaller --clean --onefile $BIN.py

mkdir -p $TARGET
cp dist/$BIN $TARGET
cp -r scripts.d $TARGET
cp README.md $TARGET
cd $TARGET
tar cvzf ../$BIN.tar $BIN