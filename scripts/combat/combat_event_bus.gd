extends RefCounted
## 战斗结算事件。监听方在自己被释放时断开，不把订阅留到下一场。

signal attack_started(context)
signal damage_resolved(result, context)
signal target_killed(result, context)
