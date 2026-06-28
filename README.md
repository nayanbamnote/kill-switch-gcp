Going forward (recommended workflow)

Local PC (development):

git add .
git commit -m "Added Cloud Function deployment"
git push

Cloud Shell (testing):

git reset --hard HEAD
git pull
chmod +x install.sh
./install.sh

This ensures Cloud Shell is always a clean copy of your repository.