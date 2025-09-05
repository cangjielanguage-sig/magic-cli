:: push.bat
@echo off

:: 启用延迟环境变量扩展（用于空值判断）
setlocal enabledelayedexpansion

:: 检查环境变量DEV_ROOT是否存在
if "!DEV_ROOT!"=="" (
    :: 未配置DEV_ROOT，提示用户配置
    echo "\%DEV_ROOT\%" env not found
    pause
    exit /b 1
) else (
    set "DEV_ROOT=!DEV_ROOT!"
)

set /p workspace=Please Input Workspace(CREATE /vendor/[Workspace] FILE On Harmony):  

call %DEV_ROOT%\cangjie-sdk-windows-1.0-ohos\cangjie\compiler\envsetup.bat

:: echo COMPILE librawinput.so...
:: %DEV_ROOT%\deveco-studio-5.1.1.804CJ.win\deveco-studio\sdk\default\openharmony\native\llvm\bin\clang.exe -B %DEV_ROOT%/cangjie-sdk-windows-1.0-ohos/cangjie/compiler/third_party/llvm/bin -B %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/sysroot/usr/lib/aarch64-linux-ohos -L %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/sysroot/usr/lib/aarch64-linux-ohos -L %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos -L %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/llvm/lib/aarch64-linux-ohos --sysroot %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/sysroot -c -fPIC ffi/raw_input_linux.c -o ffi/raw_input_linux.o
:: %DEV_ROOT%\deveco-studio-5.1.1.804CJ.win\deveco-studio\sdk\default\openharmony\native\llvm\bin\clang.exe -B %DEV_ROOT%/cangjie-sdk-windows-1.0-ohos/cangjie/compiler/third_party/llvm/bin -B %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/sysroot/usr/lib/aarch64-linux-ohos -L %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/sysroot/usr/lib/aarch64-linux-ohos -L %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos -L %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/llvm/lib/aarch64-linux-ohos --sysroot %DEV_ROOT%/deveco-studio-5.1.1.804CJ.win/deveco-studio/sdk/default/openharmony/native/sysroot -shared -o ffi/librawinput.so -target aarch64-linux-ohos ffi/raw_input_linux.o

cjpm build --target aarch64-linux-ohos -i

hdc target mount
echo =================================================SEND CANGJIE RUNTIME=================================================
for %%F in ("%DEV_ROOT%\cangjie-sdk-windows-1.0-ohos\cangjie\compiler\runtime\lib\linux_ohos_aarch64_llvm\*") do (
    hdc file send %%~fF /system/lib64
)

echo ===================================================SEND CANGJIE STDX==================================================
for %%F in ("%DEV_ROOT%\cangjie-stdx-ohos-aarch64-1.0.0.1\linux_ohos_aarch64_llvm\dynamic\stdx\*") do (
    hdc file send %%~fF /system/lib64
)

echo ====================================================   SEND FFI   ====================================================
cd ffi
hdc file send ibrawinput.so /system/lib64
cd ..

echo ====================================================SEND MAGIC LIB====================================================
soPATH=
for %%F in ("target\aarch64-linux-ohos\release\magic\*") do (
    hdc file send %%~fF /system/lib64
)

echo SEND CLI BINARY...
hdc file send "target\aarch64-linux-ohos\release\bin\cli" /system/bin
hdc shell "chmod +x /system/bin/cli"

echo PREPARE WORKSAPCE...
hdc shell mkdir -p /vendor/%workspace%
hdc shell "chmod +x /vendor/%workspace%"
hdc shell mkdir -p /vendor/%workspace%/.magic-cli
hdc file send "ohos\settings.json" /vendor/%workspace%/.magic-cli
hdc file send "ohos\.env" /vendor/%workspace%/
hdc file send "ohos\cl100k_base.tiktoken" /vendor/%workspace%/.magic-cli