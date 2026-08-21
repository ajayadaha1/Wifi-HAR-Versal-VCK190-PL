"""ESP32 8KB CSI embedding v2 (2026-05-31) — 8 -> 64 -> 128 contrastive encoder.

Drop-in compatible with the v1 feature contract: input is the same pre-extracted
8-dim CSI feature vector the RuView sensing-server already emits (`type:"feature"`).
v2 fixes the v1 trainer's broken (flat-loss) convergence; held-out temporal-triplet
accuracy improves 66.4% (raw features) -> 82.3% (this encoder), time-disjoint split.

    from safetensors.torch import load_file
    net = Enc(); net.load_state_dict(load_file("csi-embed-v2.safetensors")); net.eval()
    z = net(torch.tensor(feat8).float()[None])   # feat8: standardized 8-dim CSI feature -> 128-dim L2 embedding
"""
import torch, torch.nn as nn, torch.nn.functional as F


class Enc(nn.Module):
    def __init__(s):
        super().__init__()
        s.w1 = nn.Linear(8, 64); s.bn1 = nn.BatchNorm1d(64)
        s.w2 = nn.Linear(64, 128); s.bn2 = nn.BatchNorm1d(128)

    def forward(s, x):                       # x: [B, 8] standardized CSI features
        h = F.gelu(s.bn1(s.w1(x)))
        return F.normalize(s.bn2(s.w2(h)), dim=-1)   # -> [B, 128] L2-normalized embedding
