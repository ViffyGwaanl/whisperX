#!/bin/bash
# run.sh - 全新启动脚本，用于启动 WhisperX 项目
# 此脚本自动选择兼容的 Python（要求版本在 3.9 到 3.12 之间），若已有虚拟环境的 Python 版本不符合要求，则自动删除并重建

# 终止脚本遇到错误时退出
set -e

# 定义函数：检查 Python 版本是否符合要求（3.9 <= 版本 < 3.13）
is_acceptable_version() {
  # 参数1: 版本字符串，例如 "Python 3.12.0"
  version_str="$1"
  # 提取版本号部分
  ver=$(echo "$version_str" | awk '{print $2}')
  major=$(echo "$ver" | cut -d. -f1)
  minor=$(echo "$ver" | cut -d. -f2)
  if [ "$major" -ne 3 ]; then
    return 1
  fi
  if [ "$minor" -lt 9 ] || [ "$minor" -ge 13 ]; then
    return 1
  fi
  return 0
}

# 尝试按优先级选择兼容的 Python
PREFERRED_PYTHONS=("python3.12" "python3.11" "python3.10" "python3.9")
SELECTED_PYTHON=""
for py in "${PREFERRED_PYTHONS[@]}"; do
  if command -v "$py" >/dev/null 2>&1; then
    version=$("$py" --version 2>&1)
    if is_acceptable_version "$version"; then
      SELECTED_PYTHON="$py"
      break
    fi
  fi
done

# 如未找到，则尝试使用系统默认 python3
if [ -z "$SELECTED_PYTHON" ]; then
  default_version=$(python3 --version 2>&1)
  if is_acceptable_version "$default_version"; then
    SELECTED_PYTHON="python3"
  fi
fi

if [ -z "$SELECTED_PYTHON" ]; then
  echo "未找到兼容的 Python 版本（要求 3.9 <= 版本 < 3.13）。请安装合适的 Python 版本。"
  exit 1
fi

echo "使用 $SELECTED_PYTHON 作为兼容的 Python 版本。"

# 检查是否存在虚拟环境，并验证其 Python 版本
if [ -d "venv" ]; then
  VENV_PY_VERSION=$(./venv/bin/python --version 2>&1)
  if ! is_acceptable_version "$VENV_PY_VERSION"; then
    echo "检测到现有虚拟环境中的 Python 版本为 $VENV_PY_VERSION，不符合要求，正在删除旧虚拟环境..."
    rm -rf venv
  fi
fi

# 如果虚拟环境不存在，则创建新的虚拟环境
if [ ! -d "venv" ]; then
  echo "创建新的虚拟环境..."
  $SELECTED_PYTHON -m venv venv
fi

echo "激活虚拟环境..."
source venv/bin/activate

echo "升级 pip..."
pip install --upgrade pip

echo "安装项目依赖..."
# 尝试正常安装依赖
set +e
if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt
else
  pip install .
fi
INSTALL_EXIT_CODE=$?

# 如果安装失败，尝试安装 ctranslate2 的预发行版并重试
if [ $INSTALL_EXIT_CODE -ne 0 ]; then
  echo "普通安装依赖失败，尝试安装 ctranslate2 预发行版..."
  pip install --upgrade --pre ctranslate2
  echo "重新安装项目依赖..."
  if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
  else
    pip install .
  fi
  INSTALL_EXIT_CODE=$?
fi

# 如果依旧失败，则移除 pyproject.toml 中的 ctranslate2 和 onnxruntime==1.19 依赖后重试
if [ $INSTALL_EXIT_CODE -ne 0 ]; then
  echo "依赖安装仍失败，尝试临时移除 pyproject.toml 中的 ctranslate2 和 onnxruntime==1.19 依赖..."
  cp pyproject.toml pyproject.toml.bak
  sed -i '' -e '/ctranslate2[><=]*[0-9.]*/d' -e '/onnxruntime==1\.19/d' pyproject.toml
  echo "使用修改后的 pyproject.toml 安装依赖..."
  pip install .
  INSTALL_EXIT_CODE=$?
  mv pyproject.toml.bak pyproject.toml
fi
set -e

if [ $INSTALL_EXIT_CODE -ne 0 ]; then
  echo "安装依赖仍然失败，请检查安装日志。"
  exit $INSTALL_EXIT_CODE
fi

echo "运行 whisperx 项目..."
python -m whisperx "$@"
