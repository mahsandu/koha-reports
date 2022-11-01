SELECT bb.surname 'Suggested By', bb.cardnumber 'Member ID', r.STATUS, r.author 'Author',
r.title 'Title', r.copyrightdate 'Year', r.publishercode 'Publisher', r.isbn 'ISBN',
r.quantity 'Quantity',r.currency 'Currency', r.price 'Price', r.total 'Total Price',
b.budget_code 'Department'
 
FROM suggestions r
 
LEFT JOIN aqbudgets b ON r.budgetid=b.budget_id
LEFT JOIN borrowers bb ON r.suggestedby=bb.borrowernumber
 
WHERE STATUS LIKE 'ACCEPTED'