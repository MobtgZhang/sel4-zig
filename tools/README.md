# 工具脚本

- **`gen_vendor_manifest.py`**：根据 `vendor/sel4-src` 生成 `src/sel4/mirror_manifest.zig` 与 `docs/sel4-module-catalog.md`。在同步上游内核树后应重新执行：

```bash
python3 tools/gen_vendor_manifest.py
```
