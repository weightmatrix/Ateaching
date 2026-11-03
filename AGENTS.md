# 开发收尾约定

- 每次重要功能改动同时更新Debug和Release的版本号：MARKETING_VERSION为1.yyMMddHHmm，CURRENT_PROJECT_VERSION为yyMMddHHmm，时间使用Asia/Shanghai；三份文档记录对应版本。

- 完成用户要求的代码修改后，默认更新三份文档：`ATeaching白皮书.MD`（实现与维护）、`ATeaching说明书.MD`（用户操作）、`Ateaching开发记录.MD`（改动与验证）。
- 完成适当验证后，默认提交并推送到已配置的 GitHub 远端，不需要用户重复提醒。提交范围围绕本次任务；不要自动夹带不明来源的无关修改。
- 如构建、验证或推送失败，明确说明实际结果，不声称已完成。
- 用户明确要求只讨论、只诊断或不改代码时，遵守该次要求。
