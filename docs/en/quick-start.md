# Quick Start

Use this guide to spin up the Multicloud Surveillance demo environment in under 30 minutes.

## 1. Request Access
1. Purchase the repository access plan or redeem your invite code.
2. Fill in the GitHub username/email during checkout so we can grant permissions within one business day.
3. Download the "Start here" PDF from your confirmation email for environment defaults and FAQ links.

## 2. Prepare Your Sandbox
- Provision a single Kubernetes cluster (EKS, AKS, or GKE) or use the provided Kind script for local trials.
- Ensure outbound access to AWS Kinesis, Azure Event Hub, and Google Pub/Sub endpoints. The demo publishes synthetic events to all three clouds.
- Install the CLI bundle: `kubectl`, `helm`, and `terraform` v1.5+.

## 3. Deploy the Demo Stack
1. Clone the repository and check out the latest tag.
2. Run `./bootstrap-demo.sh` (from the PDF) to provision namespaced resources and sample streaming feeds.
3. Apply the federated dashboard manifests found in `docs/en/product-story.md` under _Storytelling Assets_.

## 4. Explore the Experience
- **Dashboards:** open the Grafana link from the bootstrap output to review occupancy heatmaps and incident drilldowns.
- **Streams:** launch the WebRTC player (URL provided in the bootstrap output) to view live and replay feeds.
- **Alerts:** trigger the sample scenarios described in `FEATURES.md` to generate PagerDuty and Slack notifications.

## 5. Share Feedback
If you need extended trials, joint demos, or custom integrations, email `solutions@multicloud-surveillance.demo` with your use case.
