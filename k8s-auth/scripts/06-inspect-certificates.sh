#!/bin/bash
# 06-inspect-certificates.sh
#
# EDUCATIONAL SCRIPT: Understanding Kubernetes Certificates
#
# This script helps you understand the certificate chain in Kubernetes
# authentication, how to inspect certificates, and common troubleshooting
# commands. Safe to run anytime - all operations are read-only.
#
# Use this script when:
#   - Learning how K8s certificates work
#   - Troubleshooting authentication failures
#   - Checking certificate expiry dates
#   - Understanding why this lab uses ngrok

set -e

# Colors for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper function for section headers
print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Helper function for sub-headers
print_subheader() {
    echo ""
    echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Helper function for info boxes
print_info() {
    echo -e "${BLUE}ℹ ${NC} $1"
}

# Helper function for educational notes
print_note() {
    echo -e "${MAGENTA}📚 ${NC}${BOLD}$1${NC}"
}

clear
echo -e "${BOLD}"
cat << 'BANNER'
   ____          _   _  __ _           _
  / ___|___ _ __| |_(_)/ _(_) ___ __ _| |_ ___
 | |   / _ \ '__| __| | |_| |/ __/ _` | __/ _ \
 | |__|  __/ |  | |_| |  _| | (_| (_| | ||  __/
  \____\___|_|   \__|_|_| |_|\___\__,_|\__\___|

  ___                           _
 |_ _|_ __  ___ _ __   ___  ___| |_ ___  _ __
  | || '_ \/ __| '_ \ / _ \/ __| __/ _ \| '__|
  | || | | \__ \ |_) |  __/ (__| || (_) | |
 |___|_| |_|___/ .__/ \___|\___|\__\___/|_|
               |_|
BANNER
echo -e "${NC}"
echo "Educational tool for understanding Kubernetes certificates"
echo "All operations are READ-ONLY and safe to run anytime"
echo ""


################################################################################
#                                                                              #
#                           MENTAL MODELS                                      #
#                                                                              #
################################################################################

print_header "MENTAL MODEL: Certificate Chains"

echo -e "${BOLD}Understanding certificates is key to troubleshooting K8s auth issues.${NC}"
echo ""
echo "Let's compare two scenarios: Production (direct) vs This Lab (ngrok tunnel)"
echo ""

print_subheader "PRODUCTION: Direct Connection to K8s API"

cat << 'DIAGRAM'

    In production, Vault connects DIRECTLY to the Kubernetes API server.
    The certificate chain is straightforward:

    ┌─────────────────────────────────────────────────────────────────────┐
    │                                                                     │
    │     KUBERNETES CA CERTIFICATE                                       │
    │     ┌─────────────────────────────────────────────────────────┐     │
    │     │  • Self-signed root of trust                            │     │
    │     │  • Created when K8s cluster is initialized              │     │
    │     │  • Used to sign all cluster certificates                │     │
    │     │  • Stored in: /etc/kubernetes/pki/ca.crt (typically)    │     │
    │     └─────────────────────────────────────────────────────────┘     │
    │                              │                                      │
    │                              │ signs                                │
    │                              ▼                                      │
    │     K8s API SERVER TLS CERTIFICATE                                  │
    │     ┌─────────────────────────────────────────────────────────┐     │
    │     │  • Presented when clients connect to API server         │     │
    │     │  • Contains SANs (Subject Alternative Names) for:       │     │
    │     │    - kubernetes, kubernetes.default                     │     │
    │     │    - API server IP address                              │     │
    │     │    - API server hostname                                │     │
    │     └─────────────────────────────────────────────────────────┘     │
    │                              │                                      │
    │                              │ verified by                          │
    │                              ▼                                      │
    │     VAULT (Client)                                                  │
    │     ┌─────────────────────────────────────────────────────────┐     │
    │     │  • Configured with: kubernetes_ca_cert                  │     │
    │     │  • Uses CA cert to verify API server's TLS cert         │     │
    │     │  • If verification fails → connection rejected          │     │
    │     │  • If CA cert expired → all auth fails!                 │     │
    │     └─────────────────────────────────────────────────────────┘     │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘

DIAGRAM

echo ""
print_note "KEY POINT: In production, Vault MUST have the K8s CA cert to verify connections."
echo ""

print_subheader "THIS LAB: ngrok Tunnel Architecture"

cat << 'DIAGRAM'

    In this lab, ngrok creates a tunnel that BYPASSES the K8s certificate chain:

    ┌─────────────────────────────────────────────────────────────────────┐
    │                                                                     │
    │     VAULT (on AWS)                                                  │
    │     ┌─────────────────────────────────────────────────────────┐     │
    │     │  • Connects to: https://xxxx.ngrok.io                   │     │
    │     │  • Sees ngrok's TLS certificate (NOT Minikube's)        │     │
    │     │  • kubernetes_ca_cert is NOT used                       │     │
    │     └─────────────────────────────────────────────────────────┘     │
    │                              │                                      │
    │                              │ HTTPS connection                     │
    │                              ▼                                      │
    │     NGROK TLS CERTIFICATE                                           │
    │     ┌─────────────────────────────────────────────────────────┐     │
    │     │  • Signed by PUBLIC CA (e.g., Let's Encrypt)            │     │
    │     │  • Valid for *.ngrok.io domain                          │     │
    │     │  • Vault trusts it via system's CA bundle               │     │
    │     │  • ngrok TERMINATES TLS here                            │     │
    │     └─────────────────────────────────────────────────────────┘     │
    │                              │                                      │
    │                              │ forwards (HTTP internally)           │
    │                              ▼                                      │
    │     MINIKUBE K8s API SERVER                                         │
    │     ┌─────────────────────────────────────────────────────────┐     │
    │     │  • Receives forwarded requests from ngrok               │     │
    │     │  • Its TLS cert is never seen by Vault                  │     │
    │     │  • Minikube CA cert is BYPASSED                         │     │
    │     └─────────────────────────────────────────────────────────┘     │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘

DIAGRAM

echo ""
print_note "KEY POINT: ngrok handles TLS, so Minikube's CA cert is not validated by Vault."
echo ""
echo -e "${YELLOW}This is why 03-configure-vault-auth.sh retrieves the CA cert but doesn't use it!${NC}"
echo ""


################################################################################
#                                                                              #
#                      CERTIFICATE INSPECTION                                  #
#                                                                              #
################################################################################

print_header "CERTIFICATE INSPECTION"

echo "Let's examine the actual certificates in this setup."
echo "We'll look at three certificates and compare them."
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl not found. Please install it first.${NC}"
    exit 1
fi

if ! minikube status &> /dev/null 2>&1; then
    echo -e "${YELLOW}WARNING: Minikube is not running. Some inspections will be skipped.${NC}"
    MINIKUBE_RUNNING=false
else
    MINIKUBE_RUNNING=true
fi


#===============================================================================
# 1. KUBERNETES CA CERTIFICATE
#===============================================================================

print_subheader "1. Kubernetes CA Certificate"

print_info "This is the root certificate that signs all K8s cluster certificates."
echo ""

if [ "$MINIKUBE_RUNNING" = true ]; then
    echo -e "${BOLD}Command to retrieve:${NC}"
    echo -e "${GREEN}kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d${NC}"
    echo ""

    # Get and display CA cert
    K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

    echo -e "${BOLD}Certificate Details:${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    echo "$K8S_CA_CERT" | openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "Could not parse certificate"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""

    # Check expiry
    EXPIRY=$(echo "$K8S_CA_CERT" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$EXPIRY" ]; then
        echo -e "${BOLD}Expiry Analysis:${NC}"
        echo "  Expires: $EXPIRY"

        # Calculate days until expiry (macOS compatible)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" "+%s" 2>/dev/null || echo "0")
        else
            EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
        fi
        NOW_EPOCH=$(date +%s)

        if [ "$EXPIRY_EPOCH" != "0" ]; then
            DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
            if [ $DAYS_LEFT -lt 30 ]; then
                echo -e "  Days remaining: ${RED}$DAYS_LEFT (EXPIRING SOON!)${NC}"
            elif [ $DAYS_LEFT -lt 90 ]; then
                echo -e "  Days remaining: ${YELLOW}$DAYS_LEFT (monitor this)${NC}"
            else
                echo -e "  Days remaining: ${GREEN}$DAYS_LEFT${NC}"
            fi
        fi
    fi
    echo ""

    # Save for later comparison
    echo "$K8S_CA_CERT" > /tmp/k8s-ca-cert.pem
    echo -e "${GREEN}✓${NC} CA cert saved to /tmp/k8s-ca-cert.pem for manual inspection"
    echo ""

    print_note "WHAT TO LOOK FOR:"
    echo "  • Subject and Issuer should be the SAME (self-signed)"
    echo "  • Check 'Not After' date - this is when it expires"
    echo "  • In production, CA certs often have 10-year validity"
else
    echo -e "${YELLOW}Skipped: Minikube not running${NC}"
fi
echo ""


#===============================================================================
# 2. K8s API SERVER TLS CERTIFICATE
#===============================================================================

print_subheader "2. K8s API Server TLS Certificate"

print_info "This certificate is presented when you connect to the K8s API server."
print_info "It should be signed by the CA certificate above."
echo ""

if [ "$MINIKUBE_RUNNING" = true ]; then
    # Get API server address
    APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    APISERVER_HOST=$(echo "$APISERVER" | sed 's|https://||' | cut -d: -f1)
    APISERVER_PORT=$(echo "$APISERVER" | sed 's|https://||' | cut -d: -f2)

    echo -e "${BOLD}API Server:${NC} $APISERVER"
    echo ""

    echo -e "${BOLD}Command to retrieve:${NC}"
    echo -e "${GREEN}echo | openssl s_client -connect ${APISERVER_HOST}:${APISERVER_PORT} 2>/dev/null | openssl x509 -noout -text${NC}"
    echo ""

    echo -e "${BOLD}Certificate Details:${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    echo | openssl s_client -connect ${APISERVER_HOST}:${APISERVER_PORT} 2>/dev/null | \
        openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "Could not retrieve certificate"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""

    # Show SANs (Subject Alternative Names)
    echo -e "${BOLD}Subject Alternative Names (SANs):${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    echo | openssl s_client -connect ${APISERVER_HOST}:${APISERVER_PORT} 2>/dev/null | \
        openssl x509 -noout -ext subjectAltName 2>/dev/null || echo "Could not retrieve SANs"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""

    print_note "WHAT TO LOOK FOR:"
    echo "  • Issuer should MATCH the CA certificate's Subject"
    echo "  • SANs should include the hostname/IP you're connecting to"
    echo "  • Error 'certificate is valid for X, not Y' = missing SAN"
else
    echo -e "${YELLOW}Skipped: Minikube not running${NC}"
fi
echo ""


#===============================================================================
# 3. NGROK TLS CERTIFICATE (for comparison)
#===============================================================================

print_subheader "3. ngrok TLS Certificate (Comparison)"

print_info "This is what Vault actually sees when connecting via ngrok."
print_info "Notice how different it is from the Minikube certificates!"
echo ""

# Check if ngrok URL is available
NGROK_URL=""
if [ -f /tmp/ngrok-k8s-url.txt ]; then
    NGROK_URL=$(cat /tmp/ngrok-k8s-url.txt)
fi

if [ -n "$NGROK_URL" ]; then
    NGROK_HOST=$(echo "$NGROK_URL" | sed 's|https://||' | cut -d/ -f1)

    echo -e "${BOLD}ngrok URL:${NC} $NGROK_URL"
    echo ""

    echo -e "${BOLD}Command to retrieve:${NC}"
    echo -e "${GREEN}echo | openssl s_client -connect ${NGROK_HOST}:443 -servername ${NGROK_HOST} 2>/dev/null | openssl x509 -noout -text${NC}"
    echo ""

    echo -e "${BOLD}Certificate Details:${NC}"
    echo "─────────────────────────────────────────────────────────────────"
    echo | openssl s_client -connect ${NGROK_HOST}:443 -servername ${NGROK_HOST} 2>/dev/null | \
        openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "Could not retrieve certificate"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""

    print_note "COMPARE WITH MINIKUBE CERTS ABOVE:"
    echo "  • Different Issuer (public CA like Let's Encrypt, not Minikube)"
    echo "  • Different Subject (*.ngrok.io, not kubernetes)"
    echo "  • This is why Vault doesn't need Minikube's CA cert in this setup!"
else
    echo -e "${YELLOW}ngrok tunnel not active. Run ./scripts/02-setup-ngrok.sh first.${NC}"
    echo ""
    echo "When ngrok is running, you'll see a certificate from a public CA"
    echo "(like Let's Encrypt or Sectigo) instead of Minikube's self-signed CA."
fi
echo ""


#===============================================================================
# 4. BONUS: ServiceAccount JWT Token
#===============================================================================

print_subheader "4. BONUS: ServiceAccount JWT Token Structure"

print_info "Pods authenticate to Vault using JWT tokens from ServiceAccounts."
print_info "Let's examine what's inside these tokens."
echo ""

if [ "$MINIKUBE_RUNNING" = true ]; then
    # Check if vault-auth token exists
    if kubectl get secret vault-auth-token -n kube-system &> /dev/null; then
        echo -e "${BOLD}Retrieving vault-auth ServiceAccount token...${NC}"
        echo ""

        TOKEN=$(kubectl get secret vault-auth-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)

        echo -e "${BOLD}JWT Token Structure:${NC}"
        echo "─────────────────────────────────────────────────────────────────"
        echo ""
        echo "A JWT has 3 parts separated by dots: HEADER.PAYLOAD.SIGNATURE"
        echo ""

        # Decode header
        echo -e "${CYAN}Header (algorithm & type):${NC}"
        echo "$TOKEN" | cut -d. -f1 | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "(could not decode)"
        echo ""

        # Decode payload
        echo -e "${CYAN}Payload (claims - what Vault validates):${NC}"
        echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "(could not decode)"
        echo ""

        echo "─────────────────────────────────────────────────────────────────"
        echo ""

        print_note "WHAT VAULT CHECKS IN THE JWT:"
        echo "  • 'iss' (issuer) - must match kubernetes_host or be disabled"
        echo "  • 'sub' (subject) - the ServiceAccount identity"
        echo "  • 'kubernetes.io/serviceaccount/namespace' - pod's namespace"
        echo "  • 'kubernetes.io/serviceaccount/service-account.name' - SA name"
    else
        echo -e "${YELLOW}vault-auth ServiceAccount not found.${NC}"
        echo "Run ./scripts/03-configure-vault-auth.sh first to create it."
    fi
else
    echo -e "${YELLOW}Skipped: Minikube not running${NC}"
fi
echo ""


################################################################################
#                                                                              #
#                      VERIFICATION CHECKLIST                                  #
#                                                                              #
################################################################################

print_header "VERIFICATION CHECKLIST"

echo "When troubleshooting certificate issues, verify these items:"
echo ""

cat << 'CHECKLIST'
    ┌─────────────────────────────────────────────────────────────────────┐
    │  CERTIFICATE VERIFICATION CHECKLIST                                 │
    ├─────────────────────────────────────────────────────────────────────┤
    │                                                                     │
    │  [ ] CA Certificate                                                 │
    │      • Not expired (check 'Not After' date)                         │
    │      • Subject matches what TLS certs show as Issuer                │
    │                                                                     │
    │  [ ] TLS Certificate                                                │
    │      • Not expired                                                  │
    │      • Issuer matches CA cert Subject                               │
    │      • SANs include the hostname/IP being used                      │
    │                                                                     │
    │  [ ] Certificate Chain                                              │
    │      • CA cert → signs → TLS cert (verify with openssl)             │
    │      • No intermediate certs missing                                │
    │                                                                     │
    │  [ ] JWT Token                                                      │
    │      • Not expired (check 'exp' claim)                              │
    │      • Issuer matches expected value                                │
    │      • ServiceAccount name/namespace are correct                    │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘
CHECKLIST
echo ""


################################################################################
#                                                                              #
#                      COMMAND REFERENCE                                       #
#                                                                              #
################################################################################

print_header "COMMAND REFERENCE CHEAT SHEET"

echo "Copy-paste these commands for certificate troubleshooting:"
echo ""

cat << 'COMMANDS'
┌─────────────────────────────────────────────────────────────────────────────┐
│  VIEWING CERTIFICATES                                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # View certificate from file                                               │
│  openssl x509 -noout -text -in cert.pem                                     │
│                                                                             │
│  # View just expiry dates                                                   │
│  openssl x509 -noout -dates -in cert.pem                                    │
│                                                                             │
│  # View subject and issuer                                                  │
│  openssl x509 -noout -subject -issuer -in cert.pem                          │
│                                                                             │
│  # View Subject Alternative Names (SANs)                                    │
│  openssl x509 -noout -ext subjectAltName -in cert.pem                       │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  FETCHING REMOTE CERTIFICATES                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Get certificate from a server                                            │
│  echo | openssl s_client -connect host:port 2>/dev/null | \                 │
│      openssl x509 -noout -text                                              │
│                                                                             │
│  # With SNI (Server Name Indication) for virtual hosts                      │
│  echo | openssl s_client -connect host:port -servername hostname \          │
│      2>/dev/null | openssl x509 -noout -text                                │
│                                                                             │
│  # Show full certificate chain                                              │
│  echo | openssl s_client -connect host:port -showcerts 2>/dev/null          │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  KUBERNETES-SPECIFIC                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Get K8s CA certificate                                                   │
│  kubectl config view --raw -o \                                             │
│      jsonpath='{.clusters[0].cluster.certificate-authority-data}' | \       │
│      base64 -d > ca.pem                                                     │
│                                                                             │
│  # Get ServiceAccount token                                                 │
│  kubectl get secret <secret-name> -o jsonpath='{.data.token}' | base64 -d   │
│                                                                             │
│  # Decode JWT token payload                                                 │
│  cat token | cut -d. -f2 | base64 -d | jq .                                 │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  VERIFICATION                                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  # Verify certificate against CA                                            │
│  openssl verify -CAfile ca.pem cert.pem                                     │
│                                                                             │
│  # Check if cert matches private key                                        │
│  diff <(openssl x509 -noout -modulus -in cert.pem) \                        │
│       <(openssl rsa -noout -modulus -in key.pem)                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
COMMANDS
echo ""


################################################################################
#                                                                              #
#                      TROUBLESHOOTING TIPS                                    #
#                                                                              #
################################################################################

print_header "TROUBLESHOOTING COMMON ERRORS"

cat << 'ERRORS'
┌─────────────────────────────────────────────────────────────────────────────┐
│  ERROR: "certificate has expired"                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  Cause: CA cert or TLS cert has passed its 'Not After' date                 │
│  Fix:   Check expiry dates on both CA and server certificates               │
│         In K8s, may need to rotate certificates (kubeadm certs renew)       │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  ERROR: "certificate signed by unknown authority"                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  Cause: Client doesn't have the CA cert that signed the server cert         │
│  Fix:   Ensure kubernetes_ca_cert is configured in Vault                    │
│         Or the CA cert is in the system's trust store                       │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  ERROR: "x509: certificate is valid for X, not Y"                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  Cause: Hostname used doesn't match any SAN in the certificate              │
│  Fix:   Check SANs with: openssl x509 -noout -ext subjectAltName -in cert   │
│         Use a hostname that's listed in the SANs                            │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  ERROR: "token issuer mismatch" (Vault K8s auth)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  Cause: JWT 'iss' claim doesn't match Vault's expected issuer               │
│  Fix:   Set disable_iss_validation=true in Vault K8s auth config            │
│         Or configure issuer parameter to match the JWT                      │
└─────────────────────────────────────────────────────────────────────────────┘
ERRORS
echo ""


################################################################################
#                                                                              #
#                           SUMMARY                                            #
#                                                                              #
################################################################################

print_header "SUMMARY"

echo "Files created during this inspection:"
echo ""
if [ -f /tmp/k8s-ca-cert.pem ]; then
    echo -e "  ${GREEN}✓${NC} /tmp/k8s-ca-cert.pem - Kubernetes CA certificate"
fi
echo ""

echo "Key takeaways:"
echo ""
echo "  1. In PRODUCTION: Vault needs the K8s CA cert to verify API server"
echo "  2. In THIS LAB: ngrok terminates TLS, so CA cert is bypassed"
echo "  3. Certificate expiry is a common cause of auth failures"
echo "  4. Always verify: CA → signs → TLS cert → matches → hostname"
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Certificate inspection complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
