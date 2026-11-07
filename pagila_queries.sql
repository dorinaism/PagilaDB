SELECT * FROM public.film LIMIT 10;

SELECT COUNT(*) AS total_movies
FROM public.film;

-- 3. Find movies longer than 120 minutes
SELECT title, length
FROM public.film
WHERE length > 120
ORDER BY length DESC;

-- Query 1. Output the number of movies in each category, sorted descending.

SELECT c.name AS category, COUNT(fc.film_id) AS movie_count
FROM public.category AS c
LEFT JOIN public.film_category AS fc ON c.category_id = fc.category_id
GROUP BY c.category_id, c.name
ORDER BY movie_count DESC, c.name;

-- Query 2. Output the 10 actors whose movies rented the most, sorted in descending order.
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    COUNT(r.rental_id) AS rental_count
FROM public.actor AS a
JOIN public.film_actor AS fa
    ON a.actor_id = fa.actor_id
JOIN public.inventory AS i
    ON fa.film_id = i.film_id
JOIN public.rental AS r
    ON i.inventory_id = r.inventory_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY rental_count DESC, a.actor_id
LIMIT 10;

-- Query 3. Output the category of movies on which the most money was spent.
WITH category_totals AS (
    SELECT c.category_id, c.name AS category, SUM(p.amount) AS total_spent
    FROM public.category AS c
    JOIN public.film_category AS fc ON c.category_id = fc.category_id
    JOIN public.inventory AS i ON fc.film_id = i.film_id
    JOIN public.rental AS r ON i.inventory_id = r.inventory_id
    JOIN public.payment AS p ON r.rental_id = p.rental_id
    GROUP BY c.category_id, c.name
), ranked AS (
    SELECT *, DENSE_RANK() OVER (ORDER BY total_spent DESC) AS category_rank
    FROM category_totals
)
SELECT category, total_spent
FROM ranked
WHERE category_rank = 1
ORDER BY category;

-- Query 4. Print the names of movies that are not in the inventory. Write a query without using the IN operator.

SELECT f.title
FROM public.film AS f
WHERE NOT EXISTS (
    SELECT 1
    FROM public.inventory AS i
    WHERE i.film_id = f.film_id
)
ORDER BY f.title;

-- Q5. All actors with one of the three highest DISTINCT Children-film counts.
-- DENSE_RANK includes ties at each count; it can return more than three actors.
-- RANK would instead select the first three positions, including boundary ties.
WITH actor_counts AS (
    SELECT a.actor_id, a.first_name, a.last_name, COUNT(*) AS movie_count
    FROM public.actor AS a
    JOIN public.film_actor AS fa ON a.actor_id = fa.actor_id
    JOIN public.film_category AS fc ON fa.film_id = fc.film_id
    JOIN public.category AS c ON fc.category_id = c.category_id
    WHERE c.name = 'Children'
    GROUP BY a.actor_id, a.first_name, a.last_name
), ranked AS (
    SELECT *, DENSE_RANK() OVER (ORDER BY movie_count DESC) AS actor_rank
    FROM actor_counts
)
SELECT first_name, last_name, movie_count
FROM ranked
WHERE actor_rank <= 3
ORDER BY movie_count DESC, last_name, first_name;

-- Q6. Customers by city; SUM(CASE ...) also works in Snowflake.
-- Check customer_id so the synthetic LEFT JOIN row is never counted.

SELECT ci.city,
       SUM(CASE WHEN cu.customer_id IS NOT NULL AND cu.active = 1
                THEN 1 ELSE 0 END) AS active_customers,
       SUM(CASE WHEN cu.customer_id IS NOT NULL AND cu.active = 0
                THEN 1 ELSE 0 END) AS inactive_customers
FROM public.city AS ci
LEFT JOIN public.address AS a ON ci.city_id = a.city_id
LEFT JOIN public.customer AS cu ON a.address_id = cu.address_id
GROUP BY ci.city_id, ci.city
ORDER BY inactive_customers DESC, ci.city;

-- Q7. Highest rental hours by category across each combined city group.
-- PostgreSQL syntax: ILIKE matches without case sensitivity;
-- EXTRACT(EPOCH FROM interval) gives seconds (divide by 3600 for hours).
-- Only returned rentals are included; all winning category ties are retained.
-- A city matching both patterns contributes independently to both groups.

WITH city_groups AS (
    SELECT city_id, 'Starts with A' AS city_group
    FROM public.city WHERE city ILIKE 'a%'
    UNION ALL
    SELECT city_id, 'Contains hyphen' AS city_group
    FROM public.city WHERE city LIKE '%-%'
), category_hours AS (
    SELECT cg.city_group, c.category_id, c.name AS category,
           SUM(EXTRACT(EPOCH FROM (r.return_date - r.rental_date)))
               / 3600.0 AS total_rental_hours
    FROM city_groups AS cg
    JOIN public.address AS a ON cg.city_id = a.city_id
    JOIN public.customer AS cu ON a.address_id = cu.address_id
    JOIN public.rental AS r ON cu.customer_id = r.customer_id
    JOIN public.inventory AS i ON r.inventory_id = i.inventory_id
    JOIN public.film_category AS fc ON i.film_id = fc.film_id
    JOIN public.category AS c ON fc.category_id = c.category_id
    WHERE r.return_date IS NOT NULL
    GROUP BY cg.city_group, c.category_id, c.name
), ranked AS (
    SELECT *, DENSE_RANK() OVER (
        PARTITION BY city_group ORDER BY total_rental_hours DESC
    ) AS category_rank
    FROM category_hours
)
SELECT city_group, category, ROUND(total_rental_hours, 2) AS total_rental_hours
FROM ranked
WHERE category_rank = 1
ORDER BY city_group, category;
