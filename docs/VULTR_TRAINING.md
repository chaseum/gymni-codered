# Training on a Vultr Cloud GPU (optional)

Vultr is for **offline training only**. The demo runs on the laptop with Wi-Fi and cloud off: live inference loads a CPU artifact from `ml/models/`. Nothing in this runbook is automated; an operator (a person) rents, uses and destroys the machine.

Only rent a GPU if the GRU comparator is worth trying. The Random Forest / k-NN baselines train on a laptop CPU in minutes.

## 0. Before renting anything

- [ ] Claim the MLH sponsor credit in the Vultr dashboard and confirm the **remaining credit** and its expiry.
- [ ] Check which GPU plans the account is eligible for and its GPU **quota**. New accounts are often limited.
- [ ] Note the hourly price of the plan you'll use. **Prices in this doc are deliberately absent: they are unverified until the operator reads them off the dashboard on the day.** Write down `price/h × planned hours` and make sure it fits the credit.
- [ ] Check dataset redistribution terms. Both datasets used here are CC BY 4.0, so copying derived landmarks to a VM is fine with attribution. **Your own recordings of people stay on the laptop** unless every person consented to cloud processing.

## 1. Prepare data on the laptop (no raw video leaves it)

Pose extraction runs locally, and only the landmark cache travels. The cache holds coordinates, not pixels.

```bash
.venv/bin/fitness-train extract --manifest ml/data/manifest.csv
```

```bash
.venv/bin/fitness-train split --manifest ml/data/manifest.csv
```

```bash
tar czf gymai-train.tgz ml/data/manifest.csv ml/data/splits.json ml/data/cache
```

The manifest holds absolute laptop video paths. Training never opens them; it reads only `ml/data/cache/` (keyed by `video_id`).

## 2. Create the instance

- Product: Cloud GPU, Ubuntu LTS image (one with NVIDIA drivers preinstalled if offered), the smallest GPU that's available. This model is tiny; a fraction of a GPU is plenty.
- Add your SSH public key at creation. Don't use password login.
- Firewall: inbound SSH (22) from your IP only.

```bash
ssh root@<instance-ip>
```

```bash
nvidia-smi
```

`nvidia-smi` must list the GPU and a driver/CUDA version. If it doesn't, stop and fix the image before going further (you're paying for idle time).

## 3. Environment on the VM

```bash
apt-get update && apt-get install -y python3-venv git
```

```bash
git clone <repo-url> gymni-codered && cd gymni-codered && python3 -m venv .venv
```

Install PyTorch **first**, with the CUDA build matching the driver from `nvidia-smi`. Use the command that the selector at https://pytorch.org/get-started/locally/ generates (Linux, Pip, Python, your CUDA version). Then:

```bash
.venv/bin/pip install -e 'ml[train]'
```

```bash
.venv/bin/python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
```

Copy the data up (run on the laptop):

```bash
scp gymai-train.tgz root@<instance-ip>:gymni-codered/ && ssh root@<instance-ip> 'cd gymni-codered && tar xzf gymai-train.tgz'
```

Check out the **same commit** you trained locally with (`git rev-parse HEAD` on the laptop). Each artifact records `code_revision`.

## 4. Train: the same CLI as the laptop

```bash
.venv/bin/fitness-train train --task recognition --model gru --device cuda
```

```bash
.venv/bin/fitness-train train --task recognition --model gru --device cpu
```

Running both on the same split checks that CPU and CUDA give comparable results; small differences are expected from non-deterministic CUDA kernels. Evaluate on the VM or later on the laptop; both read the split stored in the artifact:

```bash
.venv/bin/fitness-train evaluate --artifact ml/models/<model_version>
```

Each artifact directory contains `metadata.json`, with the `model_version`, training config, window settings, participant split lists, manifest hash, feature schema, package versions, code revision and dirty flag. Alongside it are `model.pt` (or `model.joblib`) and `metrics_test.json` after evaluation.

## 5. Bring artifacts home, then destroy the VM

Run on the laptop:

```bash
scp -r root@<instance-ip>:gymni-codered/ml/models/<model_version> ml/models/
```

Validate CPU loading and inference on the laptop:

```bash
.venv/bin/pip install -e 'ml[train,gru]'
```

```bash
.venv/bin/fitness-train evaluate --artifact ml/models/<model_version>
```

```bash
.venv/bin/fitness-ml run --source live --exercise curl --recognizer ml/models/<model_version>
```

Then, in the Vultr dashboard, **destroy** the instance. A stopped instance still bills. Delete any snapshots and block storage you created. Check that the billing page shows the instance gone.

## 6. Choosing what ships

Compare the RF / k-NN baseline and the GRU on the **identical** held-out split (`metrics_test.json`: macro-F1, per-class support, confusion matrix, per-view F1, rejection sweep). Ship whichever is better **on those numbers**. If neither beats the rules-only pipeline credibly, ship without a recognizer and say so. Report only measured numbers.

Known limitations to state with any result:
- **No deadlift video.** MyDeadlift publishes angles only, so the recognizer has no deadlift class until you add your own clips. If you do, film them in more than one place: a class that comes from a single location teaches the model the room instead of the movement.
- **Curl variation.** Multi-View curls are alternating dumbbell curls, while the live demo may be simultaneous curls.
- **Label scope.** MyDeadlift labels (rounded back, knees past toes) are whole-clip labels from that dataset's annotators. A model trained on them predicts *those labels*, not spinal safety.
