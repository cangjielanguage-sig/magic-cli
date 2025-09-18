# Magic CLI 使用指南

## 第一步：添加到环境变量

运行脚本将程序目录添加到PATH：
```
add-to-path.ps1
```

## 第二步：设置API KEY

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

## 第三步：启动程序

```
magic-cli
```

enjoy:(