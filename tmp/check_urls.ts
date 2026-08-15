// tmp/check_urls.ts
import { supabase } from '../src/services/supabase/client';

async function main() {
  const bucket = 'exercises';
  const imageDb = 'images/0001-2gPfomN.jpg';
  const gifDb = 'videos/0001-2gPfomN.gif';

  const imagePath = `assets/${imageDb}`;
  const gifPath = `assets/${gifDb}`;

  const imageUrl = supabase.storage.from(bucket).getPublicUrl(imagePath).data?.publicUrl || '';
  const gifUrl = supabase.storage.from(bucket).getPublicUrl(gifPath).data?.publicUrl || '';

  console.log('Generated Image URL:', imageUrl);
  console.log('Generated GIF URL:', gifUrl);

  try {
    const imgResp = await fetch(imageUrl);
    console.log('Image URL HTTP status:', imgResp.status);
    if (!imgResp.ok) console.log('Image URL returned error, URL:', imageUrl);
  } catch (e) {
    console.error('Error fetching image URL:', e);
  }

  try {
    const gifResp = await fetch(gifUrl);
    console.log('GIF URL HTTP status:', gifResp.status);
    if (!gifResp.ok) console.log('GIF URL returned error, URL:', gifUrl);
  } catch (e) {
    console.error('Error fetching GIF URL:', e);
  }
}

main();
