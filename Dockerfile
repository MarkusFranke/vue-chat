# first stage builds vue
FROM node:14 as build-stage
WORKDIR /build
COPY . .
RUN npm install
RUN npm run build
 
# second stage copies the static dist files and Node server files
FROM node:14 as production-stage
WORKDIR /app
COPY package.json vueBaseAppServer.js ./
COPY --from=build-stage /build/dist/ dist/
RUN npm install --production
RUN rm -rf build

# open port 3000 and run Node server
EXPOSE 3000
CMD [ "node", "vueBaseAppServer.js" ]