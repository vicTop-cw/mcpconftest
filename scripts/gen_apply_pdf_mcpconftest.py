#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_apply_pdf_mcpconftest.py —— 生成 mcpconftest 一页《项目申报书》PDF（A4，fpdf2）。
参照 FIST-Mbt/scripts/gen_apply_pdf.py 的流程与排版风格。
用法: python gen_apply_pdf_mcpconftest.py [out.pdf]
"""
import sys as _sys
if hasattr(_sys.stdout, "reconfigure"):
    _sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(_sys.stderr, "reconfigure"):
    _sys.stderr.reconfigure(encoding="utf-8", errors="replace")
import os, sys
from fpdf import FPDF

OUT = sys.argv[1] if len(sys.argv) > 1 else "项目申报书.pdf"

def find_font():
    for p in (r"C:\Windows\Fonts\simhei.ttf", r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simsun.ttc"):
        if os.path.exists(p):
            return p
    return None

class Pdf(FPDF):
    def __init__(self):
        super().__init__(format="A4")
        font = find_font()
        self.add_font("cjk", "", font)
        if font:
            self.add_font("cjk", "B", font)
            self.add_font("cjk", "I", font)
        self._has_font = font is not None
        self.set_auto_page_break(auto=False)
        self.set_margins(10, 8, 10)
        self.set_y(8)
    def hd(self, txt, size=11, bold=False):
        if not txt:
            self.ln(1.2)
            return
        self.set_font("cjk", "B" if bold else "", size)
        self.set_text_color(20, 20, 20)
        self.set_x(self.l_margin)
        self.multi_cell(0, size * 0.42, txt, new_x="LMARGIN", new_y="NEXT")
    def sec(self, txt):
        self.set_font("cjk", "B", 10)
        self.set_text_color(0, 60, 140)
        self.set_x(self.l_margin)
        self.multi_cell(0, 4.2, txt, new_x="LMARGIN", new_y="NEXT")
    def para(self, txt, size=9):
        self.set_font("cjk", "", size)
        self.set_text_color(30, 30, 30)
        self.set_x(self.l_margin)
        self.multi_cell(0, size * 0.40, txt, new_x="LMARGIN", new_y="NEXT")

pdf = Pdf()
pdf.set_title("mcpconftest 项目申报书")
pdf.add_page()
pdf.hd("mcpconftest 项目申报书", 15, True)
pdf.ln(1)
pdf.sec("1. 项目名称")
pdf.para("纯 MoonBit 编写的 MCP 协议一致性探测工具（28 类规约驱动检查，js/native 双后端，CLI + MCP Server 双形态）")
pdf.sec("2. 项目简介与状态")
pdf.para("mcpconftest 对任意 MCP Server（stdio 或 WebSocket）发起真实 JSON-RPC 会话，按 2026-07-28 协议规范逐项检查握手、能力声明、工具/资源/提示词 schema、错误路径、会话活性、幂等性、批处理、id 匹配与无状态核心（server/discover、版本协商、自描述、缺失能力、list_cache、JSON Schema 2020-12、资源错误码、MRTR、弃用标注）等 28 类检查项，输出 JSON/Markdown/HTML/JUnit 四格式报告（含逐项耗时）。")
pdf.para("当前状态：v0.8.0。28 类检查项由 specs/ 单一真源驱动（全部带 sha256 指纹），corpus/ 每类含 pass/fail 语料；JS 与 Native 双后端实测 moon check 0 错误、moon test 15/15 全绿；内建 fixture 实测 38/58 pass、15 fail（故意违规被正确检出，ALL GREEN）。CLI 四子命令（run/list-checks/version/serve）+ MCP Server 形态（暴露 run_probe/list_checks/version 三工具，内嵌 FIST-Mbt mcpcf.* 七工具）。")
pdf.sec("3. 核心亮点")
pdf.para("(1) 规格即真源：检查类别由 specs/ 机读规格运行时装配，五条铁律 L1-L5（规格即真源/双端共识/有规必有语料/无指纹不发布/破坏性变更示警）+ CI 门禁；(2) 双后端 js/native 共享同一逻辑，native 经 spawn + async/websocket 真实工作；(3) 传输双通道 stdio + WebSocket，多 Server 并行探测；(4) 报告四格式 + 逐项耗时，可入 CI 门禁；(5) MCP 化：serve 形态可被任意 MCP 客户端调用，内嵌 FIST-Mbt 自驱运维引擎（mcpcf.* 七工具，数据目录隔离）。")
pdf.sec("4. 复现证据（本次实测）")
pdf.para("moon check --target js / native：0 错误 ｜ moon test --target js / native：15/15 ｜ moon run cmd -- list-checks：28 项（含 sha256 指纹）｜ moon run cmd -- run --fixture：38/58 pass, 15 fail + ALL GREEN ｜ git：24 commits，工作区 clean。")
pdf.sec("5. 缺口补齐结论（v0.8.0 实测）")
pdf.para("原 7 项缺口已全部关闭：① serve list_checks 补齐 stateless 9 组（TOTAL=28 / STATELESS=9 / STATEFUL=19，与 CLI 一致）；② e2e fixture 补齐 7 组覆盖（38/58 pass, 15 fail, ALL GREEN）；③ README/INSTALL/USAGE 版本与演示输出校准 v0.8.0；④ License 统一 Apache-2.0；⑤ mcpconftest-report 以 v0.8.0 刷新（Pass 38/Fail 15/Skip 5）；⑥ baseline 更新至 28 类、旧申报书归档；⑦ PDF 脚本 scripts/gen_apply_pdf_mcpconftest.py 已纳入仓库（本 PDF 即由其生成）。")
pdf.sec("6. 仓库与声明")
pdf.para("仓库：https://gitcode.com/VictorTop/mcpconftest（GitHub 镜像 https://github.com/vicTop-cw/mcpconftest）；许可证 Apache-2.0。本项目广泛使用 AI 辅助生成，测试与验收证据全部可复现，README 中版本号与演示输出已校准为 v0.8.0 实测数据。")
pdf.ln(2)
pdf.para("（完整版见 项目申报书.md —— 含 28 类功能表、自驱实证轮次表、7 项缺口补齐结论、复现命令）", 8)

if not pdf._has_font:
    print("WARN: no CJK font found, output may be placeholder")
pdf.output(OUT)
print("PDF written:", OUT)
