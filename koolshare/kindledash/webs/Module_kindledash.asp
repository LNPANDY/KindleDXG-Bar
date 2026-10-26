<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge"/>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta HTTP-EQUIV="Pragma" CONTENT="no-cache"/>
<meta HTTP-EQUIV="Expires" CONTENT="-1"/>
<link rel="shortcut icon" href="images/favicon.png"/>
<link rel="icon" href="images/favicon.png"/>
<title>软件中心 - Kindle仪表盘</title>
<link rel="stylesheet" type="text/css" href="index_style.css"/>
<link rel="stylesheet" type="text/css" href="form_style.css"/>
<link rel="stylesheet" type="text/css" href="usp_style.css"/>
<link rel="stylesheet" type="text/css" href="ParentalControl.css">
<link rel="stylesheet" type="text/css" href="css/icon.css">
<link rel="stylesheet" type="text/css" href="css/element.css">
<link rel="stylesheet" type="text/css" href="/res/softcenter.css">
<script type="text/javascript" src="/js/jquery.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script type="text/javascript" src="/validator.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/switcherplugin/jquery.iphone-switch.js"></script>
<script type="text/javascript" src="/res/softcenter.js"></script>
<style>
.kindle-note {font-size:12px; color:#9CF; margin:4px 0 0 2px;}
.kindle-sec {margin-top:10px;}
td.kindle-th {width:38%;}
.kd_tag {display:inline-block; background:#2b3a42; color:#dfe; border:1px solid #567; border-radius:10px; padding:1px 8px; margin-right:6px; font-size:12px;}
.kd_tag a {color:#f96; text-decoration:none; margin-left:3px;}
</style>
<script>
var dbus = {};
var _responseLen = 0;
var BASE_COINS = ["BTC","ETH","SOL","BNB","XRP","DOGE","ADA","DOT","LINK","LTC","AVAX"];
var EXTRA = [];   // 用户手动添加的币种代码
var MODULES = [["crypto","加密货币"],["fastnews","财经快讯"],["hot","热榜"]];
var HOTS = [["","（关闭）"],["weibo","微博"],["toutiao","头条"],["zhihu","知乎"],["bilibili","B站"],["baidu","百度"],["douyin","抖音"]];
var FNS = [["sina7x24","新浪财经7×24（推荐）"],["wallstcn","华尔街见闻"],["jin10","金十数据"],["eastmoney","东方财富"],["rss","RSS聚合（下方勾选）"]];
var FEEDS = [["36kr","36氪 · 科技"],["ithome","IT之家 · 科技"],["sspai","少数派 · 数码"],["solidot","Solidot · 科技"],["sinafinance","新浪财经 · 财经"],["cointele","Cointelegraph · 区块链"],["foresight","ForesightNews · 区块链"]];

function init() {
	show_menu();
	get_dbus_data();
}

function E(id){ return document.getElementById(id); }

function opt(arr, sel) {
	var h = "";
	for (var i = 0; i < arr.length; i++) {
		var v = arr[i][0], t = arr[i][1];
		h += "<option value='" + v + "'" + (v == sel ? " selected" : "") + ">" + t + "</option>";
	}
	return h;
}

function get_dbus_data() {
	$.ajax({
		type: "GET", url: "/_api/kindledash", dataType: "json", cache: false, async: false,
		success: function(data){ dbus = data.result[0] || {}; conf2obj(); },
		error: function(){ alert("dbus 读取失败, 请刷新重试"); }
	});
}

function conf2obj() {
	E("kindledash_orientation").value = dbus["kindledash_orientation"] || "portrait";
	E("kindledash_refresh").value = dbus["kindledash_refresh"] || "15";
	var mods = (dbus["kindledash_modules"] || "crypto,fastnews,hot").split(",");
	E("kindledash_mod_1").value = mods[0] || "crypto";
	E("kindledash_mod_2").value = mods[1] || "fastnews";
	E("kindledash_mod_3").value = mods[2] || "hot";
	E("kindledash_coin_source").value = dbus["kindledash_coin_source"] || "binance";
	EXTRA = (dbus["kindledash_coins_extra"] || "").split(",").filter(function(s){return s;});
	var pv = [];
	for (var i = 1; i <= 5; i++) pv.push(dbus["kindledash_pair_" + i] || "");
	render_pool(pv);
	for (var i = 1; i <= 5; i++) E("kindledash_pair_" + i).value = pv[i-1] || "";
	for (var i = 1; i <= 5; i++) E("kindledash_pair_src_" + i).value = dbus["kindledash_pair_src_" + i] || "";
	E("kindledash_fn_source").value = dbus["kindledash_fn_source"] || "sina7x24";
	E("kindledash_fn_count").value = dbus["kindledash_fn_count"] || "4";
	for (var j = 0; j < FEEDS.length; j++) {
		var k = "kindledash_feed_" + FEEDS[j][0];
		E(k).checked = dbus[k] == "1";
	}
	E("kindledash_hot1_source").value = dbus["kindledash_hot1_source"] || "weibo";
	E("kindledash_hot2_source").value = dbus["kindledash_hot2_source"] || "bilibili";
	E("kindledash_hot_count").value = dbus["kindledash_hot_count"] || "4";
	if (dbus["kindledash_version"]) E("kd_version").innerHTML = "&nbsp;-&nbsp;v" + dbus["kindledash_version"];
}

function build_form() {
	// 把界面上的值写进 applydb 表单
	var form = document.form;
	var vals = {
		kindledash_orientation: E("kindledash_orientation").value,
		kindledash_refresh: E("kindledash_refresh").value,
		kindledash_modules: [E("kindledash_mod_1").value, E("kindledash_mod_2").value, E("kindledash_mod_3").value].filter(function(v){return v;}).join(","),
		kindledash_coin_source: E("kindledash_coin_source").value,
		kindledash_fn_source: E("kindledash_fn_source").value,
		kindledash_fn_count: E("kindledash_fn_count").value,
		kindledash_hot1_source: E("kindledash_hot1_source").value,
		kindledash_hot2_source: E("kindledash_hot2_source").value,
		kindledash_hot_count: E("kindledash_hot_count").value
	};
	for (var i = 1; i <= 5; i++) vals["kindledash_pair_" + i] = E("kindledash_pair_" + i).value;
	for (var i = 1; i <= 5; i++) vals["kindledash_pair_src_" + i] = E("kindledash_pair_src_" + i).value;
	for (var j = 0; j < FEEDS.length; j++)
		vals["kindledash_feed_" + FEEDS[j][0]] = E("kindledash_feed_" + FEEDS[j][0]).checked ? "1" : "0";
	vals["kindledash_coins_extra"] = EXTRA.join(",");
	$("[name^='kd_dyn_']").remove();
	for (var k in vals) {
		var inp = document.createElement("input");
		inp.type = "hidden";
		inp.name = k;
		inp.value = vals[k];
		form.appendChild(inp);
	}
	return vals;
}

function validate(v) {
	// 模块顺序不可重复
	var mods = [v.kindledash_modules.split(",")][0];
	var seen = {};
	for (var i = 0; i < mods.length; i++) {
		if (!mods[i]) continue;
		if (seen[mods[i]]) { alert("显示顺序里有重复模块, 请修改"); return false; }
		seen[mods[i]] = 1;
	}
	// 交易对不可重复
	var seen2 = {};
	for (var j = 1; j <= 5; j++) {
		var p = v["kindledash_pair_" + j];
		if (seen2[p]) { alert("交易对 " + p + " 重复, 请修改"); return false; }
		seen2[p] = 1;
	}
	if (v.kindledash_hot1_source && v.kindledash_hot2_source && v.kindledash_hot1_source == v.kindledash_hot2_source) {
		alert("两个热榜槽位选了同一个来源, 请修改"); return false;
	}
	return true;
}

	function call_api(id, params, fields) {
		$.ajax({
			type: "POST", url: "/_api/", data: JSON.stringify(
				{"id": id, "method": "kindledash_config.sh", "params": params, "fields": fields || {}}),
			dataType: "json",
			success: function(){ show_log(); },
			error: function(){ show_log(); }
		});
	}
	function call_api_quiet(id, params) {
		$.ajax({
			type: "POST", url: "/_api/", data: JSON.stringify(
				{"id": id, "method": "kindledash_config.sh", "params": params, "fields": {}}),
			dataType: "json"
		});
	}
	function save_apply() {
		var v = build_form();
		if (!validate(v)) return;
		// 本机 httpds 的 /applydb.cgi 会空回复断连, 保存统一走 _api fields 通道
		call_api(parseInt(Math.random() * 100000000), ["apply"], v);
	}

	function refresh_now() {
		call_api(parseInt(Math.random() * 100000000), ["render"]);
	}

	// ---------- 币种池 ----------
	function pool_arr() {
		var all = BASE_COINS.concat(EXTRA);
		return all.filter(function(v, i){ return all.indexOf(v) == i; });
	}
	function render_pool(cur) {
		if (!cur) {
			cur = [];
			for (var i = 1; i <= 5; i++) cur.push(E("kindledash_pair_" + i).value);
		}
		var p = pool_arr();
		for (var i = 1; i <= 5; i++) {
			var arr = p.map(function(c){ return [c, c]; });
			var v = cur[i-1];
			if (v && p.indexOf(v) == -1) arr.push([v, v + "（不在池内）"]);
			E("kindledash_pair_" + i).innerHTML = opt(arr, v || "");
		}
		var h = "";
		for (var i = 0; i < EXTRA.length; i++)
			h += "<span class='kd_tag'>" + EXTRA[i] +
			     "<a href='javascript:void(0)' onclick='del_coin(\"" + EXTRA[i] + "\")' title='从池中移除'>×</a></span>";
		E("kd_extra_tags").innerHTML = h || "<span style='font-size:11px;color:#9CF'>（暂无自定义币种）</span>";
	}
	function persist_extra() {
		// 静默写 dbus (不触发渲染), 同样走 _api fields 通道
		$.ajax({
			type: "POST", url: "/_api/", data: JSON.stringify(
				{"id": parseInt(Math.random() * 100000000), "method": "kindledash_config.sh",
				 "params": ["noop"], "fields": {"kindledash_coins_extra": EXTRA.join(",")}}),
			dataType: "json"
		});
	}
	function add_coin() {
		var s = E("kd_new_coin").value.trim().toUpperCase();
		if (!/^[A-Z0-9]{2,10}$/.test(s)) { alert("币种代码只能含 2~10 位字母/数字"); return; }
		if (pool_arr().indexOf(s) != -1) { alert(s + " 已在币池里"); return; }
		if (EXTRA.length >= 15) { alert("自定义币种最多 15 个"); return; }
		EXTRA.push(s);
		E("kd_new_coin").value = "";
		persist_extra();
		for (var i = 1; i <= 5; i++) {
			if (!E("kindledash_pair_" + i).value) { E("kindledash_pair_" + i).value = s; break; }
		}
		render_pool();
		E("kd_check_coin").value = s;
	}
	function del_coin(s) {
		EXTRA.splice(EXTRA.indexOf(s), 1);
		persist_extra();
		render_pool();
	}

	// ---------- 一键检测交易对 ----------
	function check_coin() {
		var s = E("kd_check_coin").value.trim().toUpperCase();
		if (!/^[A-Z0-9]{2,10}$/.test(s)) { alert("请先输入要检测的币种代码"); return; }
		var ts0 = dbus["kindledash_coincheck_ts"] || "0";
		E("kd_check_result").innerHTML = "正在检测 " + s + "（约 10 秒）...";
		call_api_quiet(parseInt(Math.random() * 100000000), ["check_coin", s]);
		var n = 0;
		var timer = setInterval(function() {
			$.ajax({
				type: "GET", url: "/_api/kindledash", dataType: "json", cache: false, async: true,
				success: function(d) {
					var nd = d.result[0] || {};
					if (nd["kindledash_coincheck_ts"] && nd["kindledash_coincheck_ts"] != ts0) {
						clearInterval(timer);
						dbus["kindledash_coincheck_ts"] = nd["kindledash_coincheck_ts"];
						var parts = (nd["kindledash_coincheck"] || "").split("|");
						var ok = {};
						for (var i = 1; i < parts.length; i++) {
							var kv = parts[i].split(":");
							ok[kv[0]] = kv[1] == "yes";
						}
						function mark(v){ return v ? "<span style='color:#3C3'>✓</span>" : "<span style='color:#F66'>✗</span>"; }
						E("kd_check_result").innerHTML = "<b>" + parts[0] + "USDT</b>　Binance " + mark(ok["binance"]) +
							"　CoinGecko " + mark(ok["coingecko"]) + "　Gate.io " + mark(ok["gate"]) +
							"<div class='kindle-note'>✓ = 该源支持此交易对，✗ = 不可达或不支持；主源选支持的那个即可</div>";
					} else if (++n > 14) {
						clearInterval(timer);
						E("kd_check_result").innerHTML = "<span style='color:#F66'>检测超时，请重试</span>";
					}
				},
				error: function() {
					if (++n > 14) { clearInterval(timer); E("kd_check_result").innerHTML = "<span style='color:#F66'>检测请求失败</span>"; }
				}
			});
		}, 1500);
	}

function show_log() {
	$("#log_tr").show();
	setTimeout(function(){ get_log(1); }, 300);
}

function get_log(flag) {
	$.ajax({
		url: '/_temp/kindledash_log.txt', type: 'GET', dataType: 'html', async: true, cache: false,
		success: function(response) {
			var retArea = E("log_content");
			retArea.value = response.replace("XU6J03M6", " ");
			retArea.scrollTop = retArea.scrollHeight;
			if (response.search("XU6J03M6") != -1 && flag) { return true; }
			if (_responseLen == response.length && response.search("XU6J03M6") == -1) {
				setTimeout("get_log(" + flag + ");", 600);
			} else {
				setTimeout("get_log(" + flag + ");", 400);
			}
			_responseLen = response.length;
		},
		error: function(xhr) {
			E("log_content").value = "暂无日志, 点击『保存并应用』或『立即刷新』后这里会显示过程日志。";
		}
	});
}
</script>
</head>
<body onload="init();">
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>
<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
<form method="POST" name="form" action="/applydb.cgi?p=kindledash_" target="hidden_frame">
<input type="hidden" name="current_page" value="Module_kindledash.asp"/>
<input type="hidden" name="next_page" value="Module_kindledash.asp"/>
<input type="hidden" name="group_id" value=""/>
<input type="hidden" name="modified" value="0"/>
<input type="hidden" name="action_mode" value=""/>
<input type="hidden" name="action_script" value=""/>
<input type="hidden" name="action_wait" value=""/>
<input type="hidden" name="first_time" value=""/>
<input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get("preferred_lang"); %>"/>
<input type="hidden" name="SystemCmd" onkeydown="onSubmitCtrl(this, ' Refresh ')" value=""/>
<input type="hidden" name="firmver" value="<% nvram_get("firmver"); %>"/>

<table class="content" align="center" cellpadding="0" cellspacing="0">
	<tr>
		<td width="17">&nbsp;</td>
		<td valign="top" width="202">
			<div id="mainMenu"></div>
			<div id="subMenu"></div>
		</td>
		<td valign="top">
			<div id="tabMenu" class="submenuBlock"></div>
			<table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
				<tr>
					<td align="left" valign="top">
						<table width="760px" border="0" cellpadding="5" cellspacing="0" bordercolor="#6b8fa3" class="FormTitle" id="FormTitle">
							<tr>
								<td bgcolor="#4D595D" colspan="3" valign="top">
									<div>&nbsp;</div>
									<div style="float:left;" class="formfonttitle">Kindle 仪表盘<span id="kd_version"></span></div>
									<div style="float:right; width:15px; height:25px;margin-top:10px"><img id="return_btn" onclick="reload_Soft_Center();" align="right" style="cursor:pointer;position:absolute;margin-left:-30px;margin-top:-25px;" title="返回软件中心" src="/images/backprev.png" onMouseOver="this.src='/images/backprevclick.png'" onMouseOut="this.src='/images/backprev.png'"></img></div>
									<div style="margin:30px 0 10px 5px;" class="splitLine"></div>
									<div class="formfontdesc" id="cmdDesc">Kindle DXG 墨水屏副屏仪表盘配置。前提：U 盘已插（Entware 就绪）、Kindle 已插在路由器 USB 口。</div>

									<!-- 基本设置 -->
									<table class="FormTable kindle-sec" width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3">
										<thead><tr><td colspan="2">基本设置</td></tr></thead>
										<tr>
											<th class="kindle-th">屏幕方向</th>
											<td>
												<select id="kindledash_orientation" class="input_option" style="width:auto">
													<option value="portrait">竖版（Kindle 正常竖持）</option>
													<option value="landscape">横版（内容旋转，Kindle 顺时针横持）</option>
												</select>
											</td>
										</tr>
										<tr>
											<th>刷新频率（分钟）</th>
											<td>
												<select id="kindledash_refresh" class="input_option" style="width:auto">
													<option value="5">5（看盘，频繁刷屏）</option>
													<option value="10">10</option>
													<option value="15">15（推荐，均衡）</option>
													<option value="20">20</option>
													<option value="30">30（省电省屏）</option>
													<option value="60">60</option>
												</select>
												<div class="kindle-note">建议 15~30 分钟：热榜/快讯 15 分钟一变已经很快；夜间内容变化小，刷太勤只是消耗墨水屏寿命</div>
											</td>
										</tr>
										<tr>
											<th>模块显示顺序</th>
											<td>
												<select id="kindledash_mod_1" class="input_option" style="width:auto"></select>
												→
												<select id="kindledash_mod_2" class="input_option" style="width:auto"></select>
												→
												<select id="kindledash_mod_3" class="input_option" style="width:auto"></select>
												<div class="kindle-note">从左到右 = 从上到下；三个都选同一模块会校验报错。想隐藏某模块？暂时把它放到最后并接受占位，后续版本支持关闭</div>
											</td>
										</tr>
									</table>

									<!-- 加密货币 -->
									<table class="FormTable kindle-sec" width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3">
										<thead><tr><td colspan="2">加密货币（固定 5 个交易对，顺序即显示顺序）</td></tr></thead>
										<tr>
											<th class="kindle-th">行情来源</th>
											<td>
												<select id="kindledash_coin_source" class="input_option" style="width:auto">
													<option value="binance">Binance（官方镜像，国内直连，推荐）</option>
													<option value="coingecko">CoinGecko（需代理网络）</option>
													<option value="gate">Gate.io（备选）</option>
												</select>
											</td>
										</tr>
										<tr>
											<th>交易对 1~5<br><span style="font-weight:normal;font-size:11px">下行可为单个币指定来源（如只有 Gate 有的币），默认跟随全局</span></th>
											<td>
												<div style="display:grid; grid-template-columns:repeat(5,1fr); gap:4px; max-width:640px">
													<select id="kindledash_pair_1" class="input_option" style="width:100%"></select>
													<select id="kindledash_pair_2" class="input_option" style="width:100%"></select>
													<select id="kindledash_pair_3" class="input_option" style="width:100%"></select>
													<select id="kindledash_pair_4" class="input_option" style="width:100%"></select>
													<select id="kindledash_pair_5" class="input_option" style="width:100%"></select>
												</div>
												<div style="display:grid; grid-template-columns:repeat(5,1fr); gap:4px; max-width:640px; margin-top:4px">
													<select id="kindledash_pair_src_1" class="input_option" style="width:100%"></select>
													<select id="kindledash_pair_src_2" class="input_option" style="width:100%"></select>
													<select id="kindledash_pair_src_3" class="input_option" style="width:100%"></select>
													<select id="kindledash_pair_src_4" class="input_option" style="width:100%"></select>
													<select id="kindledash_pair_src_5" class="input_option" style="width:100%"></select>
												</div>
											</td>
										</tr>
										<tr>
											<th class="kindle-th">添加币种<br><span style="font-weight:normal;font-size:11px">输入代码（如 PEPE、SUI），点添加后可从上方交易对里选到</span></th>
											<td>
												<input type="text" id="kd_new_coin" class="input_ss_table" style="width:90px" maxlength="10" placeholder="如 PEPE" onkeydown="if(event.keyCode==13) add_coin();">
												<input type="button" class="button_gen" style="width:70px" onclick="add_coin();" value="添加">
												<span id="kd_extra_tags" style="margin-left:6px"></span>
											</td>
										</tr>
										<tr>
											<th>交易对检测<br><span style="font-weight:normal;font-size:11px">测试该代码在三个行情源是否可用</span></th>
											<td>
												<input type="text" id="kd_check_coin" class="input_ss_table" style="width:90px" maxlength="10" placeholder="如 PEPE" onkeydown="if(event.keyCode==13) check_coin();">
												<input type="button" class="button_gen" style="width:90px" onclick="check_coin();" value="一键检测">
												<span id="kd_check_result" style="font-size:12px;margin-left:8px"></span>
											</td>
										</tr>
									</table>

									<!-- 快讯 -->
									<table class="FormTable kindle-sec" width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3">
										<thead><tr><td colspan="2">财经快讯</td></tr></thead>
										<tr>
											<th class="kindle-th">快讯来源</th>
											<td><select id="kindledash_fn_source" class="input_option" style="width:auto"></select></td>
										</tr>
										<tr>
											<th>显示条数</th>
											<td>
												<select id="kindledash_fn_count" class="input_option" style="width:auto">
													<option value="3">3</option><option value="4">4（推荐）</option>
													<option value="5">5</option><option value="6">6</option>
												</select>
											</td>
										</tr>
										<tr>
											<th>RSS 订阅池<br><span style="font-weight:normal;font-size:11px">（source=RSS 时按顺序聚合；其它快讯源挂掉时自动兜底）</span></th>
											<td id="feed_box"></td>
										</tr>
									</table>

									<!-- 热榜 -->
									<table class="FormTable kindle-sec" width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3">
										<thead><tr><td colspan="2">热榜（两个槽位并排双栏，单开一个则通栏）</td></tr></thead>
										<tr>
											<th class="kindle-th">左栏来源 / 右栏来源</th>
											<td>
												<select id="kindledash_hot1_source" class="input_option" style="width:auto"></select>
												/
												<select id="kindledash_hot2_source" class="input_option" style="width:auto"></select>
											</td>
										</tr>
										<tr>
											<th>每栏条数</th>
											<td>
												<select id="kindledash_hot_count" class="input_option" style="width:auto">
													<option value="3">3</option><option value="4">4（推荐）</option>
													<option value="5">5</option><option value="6">6</option>
												</select>
											</td>
										</tr>
									</table>

									<!-- 操作 -->
									<table class="FormTable kindle-sec" width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3">
										<thead><tr><td colspan="2">操作</td></tr></thead>
										<tr>
											<th class="kindle-th">执行</th>
											<td>
												<input type="button" id="apply_btn" class="button_gen" onclick="save_apply();" value="保存并应用">
												<input type="button" id="refresh_btn" class="button_gen" onclick="refresh_now();" value="立即刷新">
												<input type="button" id="log_btn" class="button_gen" onclick="show_log();" value="查看日志">
											</td>
										</tr>
										<tr id="log_tr" style="display:none">
											<th>过程日志</th>
											<td>
												<textarea cols="63" rows="14" wrap="off" readonly="readonly" id="log_content" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" style="border:1px solid #000;width:99%; font-family:'Courier New', Courier, mono; font-size:11px;background:#000;color:#FFFFFF;"></textarea>
											</td>
										</tr>
									</table>

									<div style="margin:10px 0 10px 5px;" class="splitLine"></div>
									<div class="KoolshareBottom">Kindle DXG 副屏项目 · 配置写入 /opt/kindle-dash/config.json · 定时任务: cru kindle-dash
									</div>
								</td>
							</tr>
						</table>
					</td>
					<td width="10" align="center" valign="top"></td>
				</tr>
			</table>
		</td>
	</tr>
</table>
</form>
<div id="footer"></div>
</body>
<script>
	// 动态下拉填充
	(function(){
		var mods = [["","（无）"]].concat(MODULES);
		E("kindledash_mod_1").innerHTML = opt(MODULES, "crypto");
		E("kindledash_mod_2").innerHTML = opt(MODULES, "fastnews");
		E("kindledash_mod_3").innerHTML = opt(MODULES, "hot");
		var ph = [["","--选择--"]].concat(BASE_COINS.map(function(c){return [c,c];}));
		for (var i = 1; i <= 5; i++) E("kindledash_pair_" + i).innerHTML = opt(BASE_COINS.map(function(c){return [c,c];}), "");
		var SRCS = [["","跟随全局"],["binance","Binance"],["coingecko","CoinGecko"],["gate","Gate"]];
		for (var i = 1; i <= 5; i++) E("kindledash_pair_src_" + i).innerHTML = opt(SRCS, "");
		E("kindledash_fn_source").innerHTML = opt(FNS, "sina7x24");
		var h = "";
		for (var j = 0; j < FEEDS.length; j++) {
			h += "<label style='margin-right:14px;white-space:nowrap'><input type='checkbox' id='kindledash_feed_" + FEEDS[j][0] + "'> " + FEEDS[j][1] + "</label>";
		}
		E("feed_box").innerHTML = h;
		E("kindledash_hot1_source").innerHTML = opt(HOTS, "weibo");
		E("kindledash_hot2_source").innerHTML = opt(HOTS, "bilibili");
	})();
</script>
</html>
