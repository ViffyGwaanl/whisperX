@echo off
:: run.bat - Windows版启动脚本，用于启动 WhisperX 项目
:: 此脚本自动选择兼容的 Python（要求版本在 3.9 到 3.12 之间），若已有虚拟环境的 Python 版本不符合要求，则自动删除并重建
:: 同时如果未指定 --compute_type 参数，则默认将其设置为 int8；如果未指定 --language 参数，则默认使用中文 "zh"

:: 终止脚本遇到错误时退出
setlocal enabledelayedexpansion
set EXIT_CODE=0

:: 定义函数：检查 Python 版本是否符合要求（3.9 <= 版本 < 3.13）
:is_acceptable_version
set version_str=%~1
for /f "tokens=2 delims= " %%a in ("%version_str%") do set ver=%%a
for /f "tokens=1,2 delims=." %%a in ("%ver%") do (
    set major=%%a
    set minor=%%b
)
if not "%major%"=="3" (
    exit /b 1
)
if %minor% LSS 9 (
    exit /b 1
)
if %minor% GEQ 13 (
    exit /b 1
)
exit /b 0

:: 尝试按优先级选择兼容的 Python
set PREFERRED_PYTHONS=python3.12 python3.11 python3.10 python3.9
set SELECTED_PYTHON=
for %%p in (%PREFERRED_PYTHONS%) do (
    where %%p >nul 2>&1
    if !errorlevel! equ 0 (
        for /f "delims=" %%v in ('%%p --version 2^>^&1') do set version=%%v
        call :is_acceptable_version "!version!"
        if !errorlevel! equ 0 (
            set SELECTED_PYTHON=%%p
            goto :found_python
        )
    )
)

:: 如未找到，则尝试使用系统默认 python3
where python3 >nul 2>&1
if !errorlevel! equ 0 (
    for /f "delims=" %%v in ('python3 --version 2^>^&1') do set version=%%v
    call :is_acceptable_version "!version!"
    if !errorlevel! equ 0 (
        set SELECTED_PYTHON=python3
        goto :found_python
    )
)

echo 未找到兼容的 Python 版本（要求 3.9 <= 版本 < 3.13）。请安装合适的 Python 版本。
exit /b 1

:found_python
echo 使用 %SELECTED_PYTHON% 作为兼容的 Python 版本。

:: 检查是否存在虚拟环境，并验证其 Python 版本
if exist venv (
    for /f "delims=" %%v in ('venv\Scripts\python --version 2^>^&1') do set VENV_PY_VERSION=%%v
    call :is_acceptable_version "!VENV_PY_VERSION!"
    if !errorlevel! neq 0 (
        echo 检测到现有虚拟环境中的 Python 版本为 !VENV_PY_VERSION!，不符合要求，正在删除旧虚拟环境...
        rmdir /s /q venv
    )
)

:: 如果虚拟环境不存在，则创建新的虚拟环境
if not exist venv (
    echo 创建新的虚拟环境...
    %SELECTED_PYTHON% -m venv venv
)

echo 激活虚拟环境...
call venv\Scripts\activate

echo 升级 pip...
python -m pip install --upgrade pip

echo 安装项目依赖...
:: 尝试正常安装依赖
if exist requirements.txt (
    python -m pip install -r requirements.txt
) else (
    python -m pip install .
)
if !errorlevel! neq 0 (
    echo 普通安装依赖失败，尝试安装 ctranslate2 预发行版...
    python -m pip install --upgrade --pre ctranslate2
    echo 重新安装项目依赖...
    if exist requirements.txt (
        python -m pip install -r requirements.txt
    ) else (
        python -m pip install .
    )
    if !errorlevel! neq 0 (
        echo 依赖安装仍失败，尝试临时移除 pyproject.toml 中的 ctranslate2 和 onnxruntime==1.19 依赖...
        copy pyproject.toml pyproject.toml.bak
        (for /f "delims=" %%a in (pyproject.toml) do (
            set "line=%%a"
            if not "!line:ctranslate2=!"=="%%a" set "line="
            if not "!line:onnxruntime==1.19=!"=="%%a" set "line="
            if defined line echo !line!
        )) > pyproject.toml.tmp
        move /y pyproject.toml.tmp pyproject.toml
        echo 使用修改后的 pyproject.toml 安装依赖...
        python -m pip install .
        move /y pyproject.toml.bak pyproject.toml
        if !errorlevel! neq 0 (
            echo 安装依赖仍然失败，请检查安装日志。
            exit /b !errorlevel!
        )
    )
)
)

:: 判断是否传入参数
if "%*"=="" (
    echo 未提供音频输入参数，显示帮助信息：
    python -m whisperx --help
) else (
    set ARGS=%*
    echo !ARGS! | find "--compute_type" >nul
    if !errorlevel! neq 0 (
        set ARGS=--compute_type int8 %ARGS%
    )
    echo !ARGS! | find "--language" >nul
    if !errorlevel! neq 0 (
        set ARGS=--language zh %ARGS%
    )
    echo 运行 whisperx 项目...
    python -m whisperx %ARGS%
    set EXIT_CODE=!errorlevel!
)

endlocal
exit /b %EXIT_CODE%
