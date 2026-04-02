# groceryGenius — Feature Ideas

*Note: Previous ideas (Trip Plan Share, Price Sparkline, Shopping List Auto-Complete) are all already implemented.*

## DONE
- ~~Shopping List Drag-to-Reorder~~ — Already implemented using framer-motion Reorder component
- ~~Store Comparison View~~ — Already implemented as PriceComparison component with /api/prices/compare/:itemId

## 1. Price Alert Notifications
Users check prices manually. A "notify me when price drops below $X" per item would be useful. Needs a notification preference UI and a background check against price history.

## 2. Shopping List Persistence
Shopping list items live in client state only. Persisting to localStorage or backend DB would prevent losing lists on page refresh.

## 3. Category Grouping in Shopping List
Auto-group items by store aisle/category (produce, dairy, etc.) to optimize shopping trips. The items table likely has category data that could drive this.
