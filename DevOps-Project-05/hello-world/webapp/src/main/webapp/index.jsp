<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%-- POST so the password never ends up in the URL, browser history or access logs.
     register.jsp is the server-side handler (the old action_page.php never existed). --%>
<form action="register.jsp" method="post" accept-charset="UTF-8">
  <div class="container">
    <h1>New user Register for DevOps Learning</h1>
    <p>Please fill in this form to create an account.</p>
    <hr>
     
    <label for="Name"><b>Enter Name</b></label>
    <input type="text" placeholder="Enter Full Name" name="Name" id="Name" required>
    <br>
    
    <label for="mobile"><b>Enter mobile</b></label>
    <input type="tel" placeholder="Enter mobile number" name="mobile" id="mobile" required>
    <br>

    <label for="email"><b>Enter Email</b></label>
    <input type="email" placeholder="Enter Email" name="email" id="email" required>
    <br>

    <label for="psw"><b>Password</b></label>
    <input type="password" placeholder="Enter Password (min. 8 characters)" name="psw" id="psw" minlength="8" required>
    <br>

    <label for="psw-repeat"><b>Repeat Password</b></label>
    <input type="password" placeholder="Repeat Password" name="psw-repeat" id="psw-repeat" required>
    <hr>
    <br>
    <p>By creating an account you agree to our <a href="#">Terms & Privacy</a>.</p>
    <button type="submit" class="registerbtn">Register</button>
  </div>
  <div class="container signin">
    <p>Already have an account? <a href="#">Sign in</a>.</p>
  </div>

   <h1> Deploy Ansible Playbook using Jenkins to automate the whole process!</h1>

  
</form>
