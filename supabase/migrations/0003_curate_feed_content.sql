delete from public.feed_items
where source_post_id in (
  select id
  from public.source_posts
  where content ~ '^RT\s+@'
     or content ~ '^https?://\S+$'
     or length(
       trim(
         regexp_replace(
           regexp_replace(content, 'https?://\S+', ' ', 'g'),
           '[@#]\w+',
           ' ',
           'g'
         )
       )
     ) < 12
);

delete from public.source_posts
where content ~ '^RT\s+@'
   or content ~ '^https?://\S+$'
   or length(
     trim(
       regexp_replace(
         regexp_replace(content, 'https?://\S+', ' ', 'g'),
         '[@#]\w+',
         ' ',
         'g'
       )
     )
   ) < 12;

update public.source_posts
set published_at = '2000-01-01T00:00:00Z'
where id like 'demo-%';

update public.feed_items
set published_at = '2000-01-01T00:00:00Z'
where source_post_id like 'demo-%'
   or id like 'feed-demo-%';
