//! HTML as values: an element is its name, its attributes and its children,
//! and text is escaped where it becomes markup, so no page can be written
//! with a value's characters read as tags.
#[derive(Clone, Debug, PartialEq)]
pub enum Node {
    Element { name: &'static str, attrs: Vec<(&'static str, String)>, children: Vec<Node> },
    Text(String),
}

/// Elements that never have children or a closing tag.
const VOID: &[&str] = &["meta", "link", "br", "hr", "img", "input"];

pub fn el(name: &'static str) -> Node {
    Node::Element { name, attrs: Vec::new(), children: Vec::new() }
}

pub fn text(s: impl Into<String>) -> Node {
    Node::Text(s.into())
}

impl Node {
    pub fn attr(mut self, key: &'static str, value: impl Into<String>) -> Node {
        if let Node::Element { attrs, .. } = &mut self {
            attrs.push((key, value.into()));
        }
        self
    }

    pub fn class(self, value: &str) -> Node {
        self.attr("class", value)
    }

    pub fn child(mut self, node: Node) -> Node {
        if let Node::Element { children, .. } = &mut self {
            children.push(node);
        }
        self
    }

    pub fn children(mut self, nodes: impl IntoIterator<Item = Node>) -> Node {
        if let Node::Element { children, .. } = &mut self {
            children.extend(nodes);
        }
        self
    }

    pub fn text(self, s: impl Into<String>) -> Node {
        self.child(text(s))
    }

    pub fn render(&self, out: &mut String) {
        match self {
            Node::Text(s) => escape(s, out),
            Node::Element { name, attrs, children } => {
                out.push('<');
                out.push_str(name);
                for (k, v) in attrs {
                    out.push(' ');
                    out.push_str(k);
                    out.push_str("=\"");
                    escape(v, out);
                    out.push('"');
                }
                out.push('>');
                if VOID.contains(name) {
                    return;
                }
                for c in children {
                    c.render(out);
                }
                out.push_str("</");
                out.push_str(name);
                out.push('>');
            }
        }
    }
}

pub fn escape(s: &str, out: &mut String) {
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            c => out.push(c),
        }
    }
}

/// A whole document.
pub fn document(root: &Node) -> String {
    let mut out = String::from("<!doctype html>");
    root.render(&mut out);
    out.push('\n');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_and_attributes_are_escaped() {
        let mut out = String::new();
        el("a").attr("href", "x\"y").text("<b> & 'c'").render(&mut out);
        assert_eq!(out, "<a href=\"x&quot;y\">&lt;b&gt; &amp; &#39;c&#39;</a>");
    }

    #[test]
    fn a_void_element_has_no_closing_tag() {
        let mut out = String::new();
        el("meta").attr("charset", "utf-8").render(&mut out);
        assert_eq!(out, "<meta charset=\"utf-8\">");
    }
}
