import pandas as pd, glob

for f in sorted(glob.glob("*.csv")):
    df = pd.read_csv(f)
    print(f, df.shape, "duplicadas:", df.duplicated().sum())
    print(df.isna().sum()[df.isna().sum() > 0])

o = pd.read_csv("olist_orders_dataset.csv", parse_dates=["order_purchase_timestamp"])
print(o.order_purchase_timestamp.min(), o.order_purchase_timestamp.max())
print(o.order_status.value_counts())

c = pd.read_csv("olist_customers_dataset.csv")
print(c.customer_unique_id.nunique())