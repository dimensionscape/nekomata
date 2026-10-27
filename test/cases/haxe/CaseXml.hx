class CaseXml {
	static function main() {
		var src = '<?xml version="1.0" encoding="UTF-8"?>
<!-- a comment -->
<root lang="en" id="r1">
	<item n="1" b="x">first &amp; foremost</item>
	<item n="2"><![CDATA[raw <data> here]]></item>
	<empty/>
	<unicode text="héllo">日本語 😀</unicode>
	<nested><a><b><c deep="yes"/></b></a></nested>
</root>';
		var x = Xml.parse(src);
		var root = x.firstElement();
		Sys.println(root.nodeName + " lang=" + root.get("lang") + " missing=" + root.get("nope") + " exists " + root.exists("id"));
		var attrs = [for (a in root.attributes()) a];
		attrs.sort(Reflect.compare);
		Sys.println(attrs);
		for (e in root.elements())
			Sys.println(e.nodeName + " " + [for (c in e) Std.string(c.nodeType)] + " [" + (e.firstChild() == null || e.firstChild().nodeType == Element ? "" : e.firstChild().nodeValue) + "]");
		for (e in root.elementsNamed("item"))
			Sys.println("item " + e.get("n"));
		var access = new haxe.xml.Access(root);
		Sys.println(access.node.unicode.att.text + " " + access.node.unicode.innerData + " " + access.nodes.item.length + " "
			+ access.node.nested.node.a.node.b.node.c.att.deep + " " + access.hasNode.empty + " " + access.has.lang);
		Sys.println(root.toString().length + " " + x.toString().length);
		Sys.println(haxe.xml.Printer.print(Xml.parse("<a x=\"1\"><b>t</b><c/></a>"), true));
		var built = Xml.createElement("built");
		built.set("k", "v & <q>");
		built.addChild(Xml.createPCData("text <escaped>"));
		built.addChild(Xml.createCData("cdata <kept>"));
		var child = Xml.createElement("child");
		built.addChild(child);
		built.removeChild(child);
		built.addChild(Xml.createComment("note"));
		Sys.println(built.toString());
		for (bad in ["<a>", "<a></b>", "<a x=1/>", "text only", "<a>&unknown;</a>"]) {
			try {
				var p = Xml.parse(bad);
				Sys.println('[$bad] parses: ' + p.toString());
			} catch (e:Dynamic) {
				Sys.println('[$bad] fails: ' + Std.string(e));
			}
		}
	}
}
