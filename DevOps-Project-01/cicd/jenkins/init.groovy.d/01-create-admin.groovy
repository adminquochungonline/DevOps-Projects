// Seed a local admin user on first boot using the credentials supplied via
// JENKINS_ADMIN_ID / JENKINS_ADMIN_PASSWORD environment variables.
// This runs because the setup wizard is disabled in the image.
import jenkins.model.Jenkins
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy

def instance = Jenkins.get()

def adminId = System.getenv('JENKINS_ADMIN_ID') ?: 'admin'
def adminPw = System.getenv('JENKINS_ADMIN_PASSWORD') ?: 'admin123'

def realm = new HudsonPrivateSecurityRealm(false)
if (realm.getAllUsers().find { it.id == adminId } == null) {
    realm.createAccount(adminId, adminPw)
    instance.setSecurityRealm(realm)

    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    instance.setAuthorizationStrategy(strategy)

    instance.save()
    println "--> Created Jenkins admin user '${adminId}'"
}
