<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" session="false" %>
<%@ page import="java.util.ArrayList, java.util.List, java.util.regex.Pattern" %>
<%--
  Handler for the registration form in index.jsp.
  Demo scope: validates the input server-side and confirms the registration.
  Nothing is stored (the app has no database) and the password is never echoed.
--%>
<%!
    private static final Pattern EMAIL  = Pattern.compile("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$");
    private static final Pattern MOBILE = Pattern.compile("^\\+?[0-9 ]{8,15}$");

    private static String trim(String s) {
        return s == null ? "" : s.trim();
    }

    // Minimal HTML escaping: user input is echoed back, so it must not be able
    // to inject markup or script (no JSTL <c:out> in this project).
    private static String esc(String s) {
        StringBuilder out = new StringBuilder(s.length());
        for (char c : s.toCharArray()) {
            switch (c) {
                case '<':  out.append("&lt;");   break;
                case '>':  out.append("&gt;");   break;
                case '&':  out.append("&amp;");  break;
                case '"':  out.append("&quot;"); break;
                case '\'': out.append("&#39;");  break;
                default:   out.append(c);
            }
        }
        return out.toString();
    }
%>
<%
    // Direct GET (bookmark, refresh after redirect): send the user to the form.
    if (!"POST".equalsIgnoreCase(request.getMethod())) {
        response.sendRedirect(request.getContextPath() + "/");
        return;
    }
    request.setCharacterEncoding("UTF-8");

    String name      = trim(request.getParameter("Name"));
    String mobile    = trim(request.getParameter("mobile"));
    String email     = trim(request.getParameter("email"));
    String psw       = request.getParameter("psw") == null ? "" : request.getParameter("psw");
    String pswRepeat = request.getParameter("psw-repeat") == null ? "" : request.getParameter("psw-repeat");

    List<String> errors = new ArrayList<String>();
    if (name.isEmpty() || name.length() > 100) {
        errors.add("Name is required (max. 100 characters).");
    }
    if (!MOBILE.matcher(mobile).matches()) {
        errors.add("Mobile number must be 8-15 digits (an optional leading + is allowed).");
    }
    if (email.length() > 254 || !EMAIL.matcher(email).matches()) {
        errors.add("Email address is not valid.");
    }
    if (psw.length() < 8) {
        errors.add("Password must be at least 8 characters.");
    }
    if (!psw.equals(pswRepeat)) {
        errors.add("Passwords do not match.");
    }

    if (!errors.isEmpty()) {
        response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
    }
%>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title><%= errors.isEmpty() ? "Registration successful" : "Registration failed" %></title>
</head>
<body>
  <div class="container">
<% if (errors.isEmpty()) { %>
    <h1>Registration successful</h1>
    <p>Welcome, <b><%= esc(name) %></b>! Your account for DevOps Learning has been created.</p>
    <ul>
      <li>Email: <%= esc(email) %></li>
      <li>Mobile: <%= esc(mobile) %></li>
    </ul>
    <p><a href="<%= request.getContextPath() %>/">Register another user</a></p>
<% } else { %>
    <h1>Registration failed</h1>
    <p role="alert">Please fix the following and try again:</p>
    <ul>
<%     for (String e : errors) { %>
      <li><%= esc(e) %></li>
<%     } %>
    </ul>
    <p><a href="javascript:history.back()">Back to the form</a></p>
<% } %>
  </div>
</body>
</html>
