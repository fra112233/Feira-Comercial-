-- 077: o armazenamento das fotos dos anúncios (ads_media) é público e aceitava qualquer tipo de ficheiro.
-- O site só envia fotos JPEG; limitar a imagens impede que alguém aloje páginas HTML/SVG
-- (por exemplo, páginas falsas de login) num endereço do nosso Supabase.
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id = 'ads_media';
