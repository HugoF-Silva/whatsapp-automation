# import numpy as np

# x = np.array([10, 33, 47, 3, 2, 11])
# weights = np.array([0.8, 0.6, 0, 0.2, 0.2, 0.4])
# # weights = np.array([0.8, 0.6, 0, 0.2, 0.2, 0.4])
# i_sort = np.argsort(x)
# x = x[i_sort]
# weights = weights[i_sort]
# cum_weights = np.cumsum(weights)
# cutoff = cum_weights[-1]/2
# print(x)
# print(weights)
# print(cum_weights)
# print(cutoff)
# median_idx = np.searchsorted(cum_weights, cutoff, side='left')
# print(x[median_idx])


# import numpy as np

# def softmax(x):
#     e_x = np.exp(x - np.max(x))  # subtract max(x) for numerical stability
#     return e_x / e_x.sum()

# arr = [20, 30, 50]
# result = softmax(arr)
# print(result)
# print(result.sum())


# def l1_normalize(a):
#     """
#     Return the L1-normalized version of array a,
#     i.e. a / sum(|a|). If the sum of absolute values is zero,
#     raises a ValueError.
#     """
#     a = np.asarray(a, dtype=float)
#     norm = np.abs(a).sum()
#     if norm == 0:
#         raise ValueError("Cannot L1‑normalize: sum of absolute values is zero.")
#     return a / norm

# # Example usage:
# weights = [3, 2]
# print(l1_normalize(weights))
# # → [0.2 0.3 0.5]   (already sums to 1)

est = 3 * 2 + 1 * 4
print(est)