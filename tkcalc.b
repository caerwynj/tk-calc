implement Tkcalc;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image: import draw;

include "tk.m";
	tk: Tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "string.m";
	str: String;

Tkcalc: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

tkcfg(): array of string
{
	return  array[] of {
	"frame .main -bg #202020 -borderwidth 2 -relief ridge",
	"wm geometry . 360x460",
	"wm minsize . 320 420",
	"frame .dispframe -bg black -borderwidth 2 -relief sunken",
	"label .disp -bg gray -fg white -anchor e -text 0 -width 18 -height 2",
	"frame .keys -bg #202020",

	"frame .r0 -bg #202020",
	"button .b7 -text 7 -command {send cmd 7} -width 17 -height 13",
	"button .b8 -text 8 -command {send cmd 8} -width 17 -height 13",
	"button .b9 -text 9 -command {send cmd 9} -width 17 -height 13",
	"button .bdiv -text / -command {send cmd /} -width 17 -height 13",
	"pack .b7 .b8 .b9 .bdiv -in .r0 -side left -expand 1 -fill both -padx 2 -pady 2",

	"frame .r1 -bg #202020",
	"button .b4 -text 4 -command {send cmd 4} -width 17 -height 13",
	"button .b5 -text 5 -command {send cmd 5} -width 17 -height 13",
	"button .b6 -text 6 -command {send cmd 6} -width 17 -height 13",
	"button .bmul -text * -command {send cmd *} -width 17 -height 13",
	"pack .b4 .b5 .b6 .bmul -in .r1 -side left -expand 1 -fill both -padx 2 -pady 2",

	"frame .r2 -bg #202020",
	"button .b1 -text 1 -command {send cmd 1} -width 17 -height 13",
	"button .b2 -text 2 -command {send cmd 2} -width 17 -height 13",
	"button .b3 -text 3 -command {send cmd 3} -width 17 -height 13",
	"button .bsub -text - -command {send cmd -} -width 17 -height 13",
	"pack .b1 .b2 .b3 .bsub -in .r2 -side left -expand 1 -fill both -padx 2 -pady 2",

	"frame .r3 -bg #202020",
	"button .b0 -text 0 -command {send cmd 0} -width 17 -height 13",
	"button .bdot -text . -command {send cmd .} -width 17 -height 13",
	"button .beq -text = -command {send cmd =} -width 17 -height 13",
	"button .badd -text + -command {send cmd +} -width 17 -height 13",
	"pack .b0 .bdot .beq .badd -in .r3 -side left -expand 1 -fill both -padx 2 -pady 2",

	"frame .r4 -bg #202020",
	"button .bclr -text C -command {send cmd C} -width 17 -height 13",
	"pack .bclr -in .r4 -side left -expand 1 -fill both -padx 2 -pady 2",

	"pack .r0 .r1 .r2 .r3 .r4 -in .keys -fill x",
	"pack .disp -in .dispframe -fill x -padx 6 -pady 6 -ipady 6",
	"pack .dispframe -in .main -fill x -padx 8 -pady 8",
	"pack .keys -in .main -fill both -expand 1 -padx 6 -pady 6",
	"pack .main -fill both -expand 1",
	"pack propagate . 1",
	"update",
	};
}

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "about: no window context\n");
		raise "fail:bad context";
	}

	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;
	str = load String String->PATH;

	tkclient->init();
	(t, menubut) := tkclient->toplevel(ctxt, "", "Calc", 0);

	cmdchan := chan of string;
	tk->namechan(t, cmdchan, "cmd");

	tkcmds := tkcfg();
	for (i := 0; i < len tkcmds; i++)
		tk->cmd(t,tkcmds[i]);

	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "ptr"::nil);
	stop := chan of int;
	spawn tkclient->handler(t, stop);

	acc := 0.0;
	haveacc := 0;
	pending := "";
	cur := "0";
	newnum := 1;
	err := 0;
	setdisp(t, cur, err);

	for(;;) {
		done := 0;
		alt {
		menu := <-menubut =>
			if(menu == "exit")
				done = 1;
			else
				tkclient->wmctl(t, menu);
		msg := <-cmdchan =>
			(cur, acc, haveacc, pending, newnum, err) =
				handle(msg, cur, acc, haveacc, pending, newnum, err);
			setdisp(t, cur, err);
		}
		if(done)
			break;
	}
	stop <-= 1;
}

setdisp(t: ref Tk->Toplevel, cur: string, err: int)
{
	if(err)
		tk->cmd(t, ".disp configure -text " + tk->quote("Err"));
	else
		tk->cmd(t, ".disp configure -text " + tk->quote(cur));
	tk->cmd(t, "update");
}

handle(msg, cur: string, acc: real, haveacc: int, pending: string, newnum: int, err: int):
	(string, real, int, string, int, int)
{
	if(msg == "C") {
		return ("0", 0.0, 0, "", 1, 0);
	}

	if(err) {
		if(msg == "=")
			return (cur, acc, haveacc, pending, newnum, err);
		return handle(msg, "0", 0.0, 0, "", 1, 0);
	}

	if(isdigit(msg) || msg == ".") {
		if(newnum) {
			if(msg == ".")
				cur = "0.";
			else
				cur = msg;
			newnum = 0;
		} else {
			if(msg == "." && str->contains(cur, ".") > 0)
				return (cur, acc, haveacc, pending, newnum, err);
			cur += msg;
		}
		return (cur, acc, haveacc, pending, newnum, err);
	}

	if(msg == "+" || msg == "-" || msg == "*" || msg == "/" || msg == "=") {
		(val, rest) := str->toreal(cur, 10);
		if(rest != nil && rest != "") {
			return (cur, acc, haveacc, pending, newnum, 1);
		}
		if(haveacc) {
			(acc, err) = apply(pending, acc, val);
		} else {
			acc = val;
			haveacc = 1;
		}
		if(msg == "=") {
			cur = fmt(acc);
			pending = "";
			newnum = 1;
		} else {
			pending = msg;
			cur = fmt(acc);
			newnum = 1;
		}
		return (cur, acc, haveacc, pending, newnum, err);
	}

	return (cur, acc, haveacc, pending, newnum, err);
}

isdigit(s: string): int
{
	return len s == 1 && s[0] >= '0' && s[0] <= '9';
}

apply(op: string, a, b: real): (real, int)
{
	if(op == "+")
		return (a + b, 0);
	if(op == "-")
		return (a - b, 0);
	if(op == "*")
		return (a * b, 0);
	if(op == "/") {
		if(b == 0.0)
			return (a, 1);
		return (a / b, 0);
	}
	return (b, 0);
}

fmt(v: real): string
{
	return sys->sprint("%g", v);
}
