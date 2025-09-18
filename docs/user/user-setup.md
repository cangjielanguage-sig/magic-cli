# Magic CLI 使用指南

## 第一步：设置仓颉环境

前置要求安装好 Cangjie SDK 环境，并设置好 `CANGJIE_HOME` 或者单次会话中在 powershell 执行：

```powershell
. path\to\cangjie\envsetup.ps1
```

具体参考仓颉官方文档：
https://cangjie-lang.cn/docs?url=%2F1.0.0%2Fuser_manual%2Fsource_zh_cn%2Ffirst_understanding%2Finstall_Community.html

## 第二步：添加到环境变量

运行脚本将程序目录添加到PATH：
```
add-to-path.ps1
```

## 第三步：设置API KEY

**临时设置：**

命令提示符：
```cmd
set ARK_API_KEY=your_api_key_here
```

PowerShell：
```powershell
$env:ARK_API_KEY="your_api_key_here"
```

**永久设置：**

命令提示符：
```cmd
setx ARK_API_KEY your_api_key_here
```

PowerShell：
```powershell
[Environment]::SetEnvironmentVariable("ARK_API_KEY", "your_api_key_here", "User")
```

## 第四步：启动程序

```
magic-cli
```

enjoy:(