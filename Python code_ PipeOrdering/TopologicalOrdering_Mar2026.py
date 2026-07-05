import pandas as pd
import networkx as nx

links_file = "InputFile_PETBR_17k.csv"
output_file = "OutputFile_PETBR_17k.csv"
cuts_report_file = "cuts_report_Final.csv"

# ============================================================
# Load
# ============================================================
links = pd.read_csv(links_file)
required = {"link_id", "from_node", "to_node", "link_index"}
missing = required - set(links.columns)
if missing:
    raise ValueError(f"Missing required columns: {missing}")

has_dwf = "DWF" in links.columns

# Keep a working copy
links_work = links.copy()

# ============================================================
# Build graphs
#   G_multi: full multigraph with edge attributes
#   DG: simple digraph used only for cycle detection / topo sort
# ============================================================
def build_graphs(df):
    G_multi = nx.MultiDiGraph()
    DG = nx.DiGraph()

    for r in df.itertuples(index=False):
        edge_data = {
            "link_id": r.link_id,
            "link_index": int(r.link_index),
        }
        if has_dwf:
            val = getattr(r, "DWF")
            edge_data["DWF"] = float(val) if pd.notna(val) else float("inf")

        u = r.from_node
        v = r.to_node
        k = int(r.link_index)

        G_multi.add_edge(u, v, key=k, **edge_data)
        DG.add_edge(u, v)

    return G_multi, DG

G_multi, DG = build_graphs(links_work)

# ============================================================
# Edge scoring for cutting
# Lower score = more preferred to cut
# Tune this function as needed
# ============================================================
def cut_score(edge_data):
    dwf = edge_data.get("DWF", float("inf"))
    link_index = edge_data["link_index"]
    return (dwf, link_index)

# ============================================================
# Find one cycle and cut one edge from it
# ============================================================
cut_rows = []
cut_counter = 0

while True:
    try:
        cycle_nodes = nx.find_cycle(DG, orientation="original")
    except nx.NetworkXNoCycle:
        break

    # cycle_nodes is a list like [(u1,v1,_), (u2,v2,_), ...]
    candidate_edges = []

    for item in cycle_nodes:
        u, v = item[0], item[1]

        # There may be multiple parallel edges u->v in G_multi
        edge_dict = G_multi.get_edge_data(u, v)
        if edge_dict is None:
            continue

        for k, data in edge_dict.items():
            candidate_edges.append((u, v, k, data))

    if not candidate_edges:
        raise RuntimeError("Cycle found in DG but no matching edges found in G_multi.")

    # Pick the least important edge in this cycle
    u_cut, v_cut, k_cut, data_cut = min(candidate_edges, key=lambda x: cut_score(x[3]))

    cut_counter += 1
    split_node = f"{v_cut}__split{cut_counter}"

    # In the multigraph: reroute the chosen edge to a dead-end split node
    G_multi.add_node(split_node)
    G_multi.add_edge(u_cut, split_node, key=k_cut, **data_cut)
    G_multi.remove_edge(u_cut, v_cut, k_cut)

    # In the simple graph: remove original arc; add rerouted arc
    if DG.has_edge(u_cut, v_cut):
        # Remove and rebuild carefully in case parallel edges remain in multigraph
        DG.remove_edge(u_cut, v_cut)

        # If another parallel edge still exists in G_multi from u_cut to v_cut,
        # restore the simple edge in DG
        remaining = G_multi.get_edge_data(u_cut, v_cut)
        if remaining is not None and len(remaining) > 0:
            DG.add_edge(u_cut, v_cut)

    DG.add_edge(u_cut, split_node)

    cut_rows.append({
        "cut_id": cut_counter,
        "from_node": u_cut,
        "to_node": v_cut,
        "split_node": split_node,
        "link_index": data_cut["link_index"],
        "link_id": data_cut["link_id"],
        "DWF": data_cut.get("DWF", None),
        "reason": "cycle cut: minimum score in detected cycle"
    })

    print(
        f"Cut {cut_counter}: {u_cut} -> {v_cut} "
        f"(link_id={data_cut['link_id']}, link_index={data_cut['link_index']})"
    )

# ============================================================
# Final DAG check
# ============================================================
if not nx.is_directed_acyclic_graph(DG):
    raise RuntimeError("Graph still cyclic after all cycle cuts.")

# ============================================================
# Topological generations
# ============================================================
node_gen = {}
for n in nx.topological_sort(DG):
    preds = list(DG.predecessors(n))
    node_gen[n] = 1 if not preds else max(node_gen[p] for p in preds) + 1

# ============================================================
# Upstream link lists from original links table
# ============================================================
to_node_groups = {}
for r in links.itertuples(index=False):
    to_node_groups.setdefault(r.to_node, []).append(int(r.link_index))

rows = []
for r in links.sort_values("link_index").itertuples(index=False):
    idx = int(r.link_index)
    u = r.from_node
    v = r.to_node
    gen = node_gen.get(u, 1)

    upstream = sorted(to_node_groups.get(u, []))
    upstream_str = "[]" if not upstream else "[" + " ".join(map(str, upstream)) + "]"

    rows.append({
        "link_index": idx,
        "link_id": r.link_id,
        "from_node": u,
        "to_node": v,
        "generation": gen,
        "upstream_list": upstream_str
    })

pd.DataFrame(rows).sort_values("link_index").to_csv(output_file, index=False)

if cut_rows:
    pd.DataFrame(cut_rows).to_csv(cuts_report_file, index=False)

print(f"Saved generation map to {output_file}")
print(f"Saved cuts report to {cuts_report_file}")